# Copyright (C) 2023 Felix Geilert

import sys

import pytest

# if using 'bazel test ...'
if __name__ == "__main__":
    # TODO: adjust this to make sure this only calls relevant pytests?
    # TODO: print warning if no locations are provided
    sys.exit(pytest.main(sys.argv[1:]))
    # FEAT: handle errors and print to console?
