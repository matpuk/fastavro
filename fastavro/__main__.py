import datetime
from decimal import Decimal
import json
from sys import stdout
from uuid import UUID

import fastavro as avro

encoding = stdout.encoding or "UTF-8"


def _clean_json_value(collection, key, value):
    if isinstance(value, (datetime.date, datetime.datetime)):
        collection[key] = value.isoformat()
    elif isinstance(value, (Decimal, UUID)):
        collection[key] = str(value)
    else:
        _clean_json_record(value)


def _clean_json_record(data):
    if isinstance(data, dict):
        for k, v in data.items():
            _clean_json_value(data, k, v)
    elif isinstance(data, list):
        for i, v in enumerate(data):
            _clean_json_value(data, i, v)


def main(argv=None):
    import sys
    from argparse import ArgumentParser

    argv = argv or sys.argv

    parser = ArgumentParser(
        description='iter over avro file, emit records as JSON')
    parser.add_argument('file', help="file(s) to parse, use `-' for stdin",
                        nargs='*')
    parser.add_argument('--schema', help='dump schema instead of records',
                        action='store_true', default=False)
    parser.add_argument('--metadata', help='dump metadata instead of records',
                        action='store_true', default=False)
    parser.add_argument('--codecs', help='print supported codecs',
                        action='store_true', default=False)
    parser.add_argument('--version', action='version',
                        version='fastavro %s' % avro.__version__)
    parser.add_argument('-p', '--pretty', help='pretty print json',
                        action='store_true', default=False)
    args = parser.parse_args(argv[1:])

    if args.codecs:
        print('\n'.join(sorted(avro.read.BLOCK_READERS)))
        exit(0)

    files = args.file or ['-']
    for filename in files:
        if filename == '-':
            fo = sys.stdin.buffer
        else:
            fo = open(filename, 'rb')

        reader = avro.reader(fo)

        if args.schema:
            json.dump(reader.schema, sys.stdout, indent=True)
            sys.stdout.write('\n')
            continue

        elif args.metadata:
            del reader.metadata['avro.schema']
            json.dump(reader.metadata, sys.stdout, indent=True)
            sys.stdout.write('\n')
            continue

        indent = 4 if args.pretty else None
        for record in reader:
            _clean_json_record(record)
            json.dump(record, sys.stdout, indent=indent)
            sys.stdout.write('\n')
            sys.stdout.flush()


if __name__ == '__main__':
    main()
