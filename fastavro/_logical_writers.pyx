# cython: language_level=3str

import datetime

import decimal
import os
import uuid

from libc.time cimport tm, mktime
from cpython.int cimport PyInt_AS_LONG
from cpython.tuple cimport PyTuple_GET_ITEM

from fastavro import const

ctypedef long long long64

cdef long64 MCS_PER_SECOND = const.MCS_PER_SECOND
cdef long64 MCS_PER_MINUTE = const.MCS_PER_MINUTE
cdef long64 MCS_PER_HOUR = const.MCS_PER_HOUR

cdef long64 MLS_PER_SECOND = const.MLS_PER_SECOND
cdef long64 MLS_PER_MINUTE = const.MLS_PER_MINUTE
cdef long64 MLS_PER_HOUR = const.MLS_PER_HOUR

cdef is_windows = os.name == 'nt'
epoch_naive = datetime.datetime(1970, 1, 1)


cpdef prepare_timestamp_millis(object data, schema):
    if isinstance(data, datetime.datetime):
        # On Windows, timestamps before the epoch will raise an error.
        # See https://bugs.python.org/issue36439
        if is_windows and data.tzinfo is None:
            return <long64>(<double>(
                <object>(data - epoch_naive).total_seconds()) * MLS_PER_SECOND
            )
        else:
            return <long64>(<double>(data.timestamp()) * MLS_PER_SECOND)
    else:
        return data


cpdef prepare_timestamp_micros(object data, schema):
    if isinstance(data, datetime.datetime):
        # On Windows, timestamps before the epoch will raise an error.
        # See https://bugs.python.org/issue36439
        if is_windows and data.tzinfo is None:
            return <long64>(<double>(
                <object>(data - epoch_naive).total_seconds()) * MCS_PER_SECOND
            )
        else:
            return <long64>(<double>(data.timestamp()) * MCS_PER_SECOND)
    else:
        return data


cpdef prepare_date(object data, schema):
    if isinstance(data, datetime.date):
        return data.toordinal() - const.DAYS_SHIFT
    elif isinstance(data, str):
        return datetime.datetime.strptime(data, "%Y-%m-%d").toordinal() - const.DAYS_SHIFT
    else:
        return data


cpdef prepare_bytes_decimal(object data, schema):
    """Convert decimal.Decimal to bytes"""
    if not isinstance(data, decimal.Decimal):
        return data
    scale = schema.get('scale', 0)

    sign, digits, exp = data.as_tuple()

    delta = exp + scale

    if delta < 0:
        raise ValueError(
            'Scale provided in schema does not match the decimal')

    unscaled_datum = 0
    for digit in digits:
        unscaled_datum = (unscaled_datum * 10) + digit

    unscaled_datum = 10 ** delta * unscaled_datum

    bytes_req = (unscaled_datum.bit_length() + 8) // 8

    if sign:
        unscaled_datum = -unscaled_datum

    return unscaled_datum.to_bytes(bytes_req, byteorder='big', signed=True)


cpdef prepare_fixed_decimal(object data, schema):
    cdef bytearray tmp
    if not isinstance(data, decimal.Decimal):
        return data
    scale = schema.get('scale', 0)
    size = schema['size']

    # based on https://github.com/apache/avro/pull/82/

    sign, digits, exp = data.as_tuple()

    if -exp > scale:
        raise ValueError(
            'Scale provided in schema does not match the decimal')
    delta = exp + scale
    if delta > 0:
        digits = digits + (0,) * delta

    unscaled_datum = 0
    for digit in digits:
        unscaled_datum = (unscaled_datum * 10) + digit

    bits_req = unscaled_datum.bit_length() + 1

    size_in_bits = size * 8
    offset_bits = size_in_bits - bits_req

    mask = 2 ** size_in_bits - 1
    bit = 1
    for i in range(bits_req):
        mask ^= bit
        bit <<= 1

    if bits_req < 8:
        bytes_req = 1
    else:
        bytes_req = bits_req // 8
        if bits_req % 8 != 0:
            bytes_req += 1

    tmp = bytearray()

    if sign:
        unscaled_datum = (1 << bits_req) - unscaled_datum
        unscaled_datum = mask | unscaled_datum
        for index in range(size - 1, -1, -1):
            bits_to_write = unscaled_datum >> (8 * index)
            tmp += bytes([bits_to_write & 0xff])
    else:
        for i in range(offset_bits // 8):
            tmp += bytes([0])
        for index in range(bytes_req - 1, -1, -1):
            bits_to_write = unscaled_datum >> (8 * index)
            tmp += bytes([bits_to_write & 0xff])

    return tmp


cpdef prepare_uuid(object data, schema):
    if isinstance(data, uuid.UUID):
        return str(data)
    else:
        return data


cpdef prepare_time_millis(object data, schema):
    if isinstance(data, datetime.time):
        return int(
            data.hour * MLS_PER_HOUR + data.minute * MLS_PER_MINUTE
            + data.second * MLS_PER_SECOND + int(data.microsecond / 1000))
    else:
        return data


cpdef prepare_time_micros(object data, schema):
    if isinstance(data, datetime.time):
        return int(data.hour * MCS_PER_HOUR + data.minute * MCS_PER_MINUTE
                   + data.second * MCS_PER_SECOND + data.microsecond)
    else:
        return data


LOGICAL_WRITERS = {
    'long-timestamp-millis': prepare_timestamp_millis,
    'long-timestamp-micros': prepare_timestamp_micros,
    'int-date': prepare_date,
    'bytes-decimal': prepare_bytes_decimal,
    'fixed-decimal': prepare_fixed_decimal,
    'string-uuid': prepare_uuid,
    'int-time-millis': prepare_time_millis,
    'long-time-micros': prepare_time_micros,

}
