"""Testing Script for python to validate if all language features are working.

Copyright (c) 2024 Radiant Science Inc.
"""

from samples.python.hello_lib import get_proto


def main() -> None:
    sample_message = get_proto()
    print(sample_message)

    print("Hello World")


if __name__ == "__main__":
    main()
