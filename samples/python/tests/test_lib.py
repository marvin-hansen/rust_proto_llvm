"""Unit Test for the Python Library.

Copyright (c) 2024 Radiant Science Inc.
"""

from datetime import (
    datetime,
    timedelta,
)

import pytest
from samples.python.hello_lib import get_proto


def test_get_proto() -> None:
    proto = get_proto()
    assert proto.name == "python"
    assert proto.tags == ["foo", "bar"]
    assert len(proto.subs) == 2
    assert proto.subs[0].flag
    assert pytest.approx(proto.subs[0].value) == 42.1984
    assert not proto.subs[1].flag
    assert pytest.approx(proto.subs[1].value) == -42.1984
    assert proto.meta.flag
    assert pytest.approx(proto.meta.value) == 42.1984
    dt = proto.time.ToDatetime()
    assert isinstance(dt, datetime)
    assert dt < datetime.now()
    assert dt > datetime.now() - timedelta(minutes=15)
    td = proto.duration.ToTimedelta()
    assert isinstance(td, timedelta)
    assert td == timedelta(days=1)
