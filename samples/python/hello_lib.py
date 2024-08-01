"""Simple Library Test for Python.

Copyright (c) 2024 Radiant Science Inc.
"""

from datetime import (
    datetime,
    timedelta,
)

from samples.proto.sample_pb2 import SampleMessage


def get_proto() -> SampleMessage:
    """Generates a simple proto message.

    Returns:
        SampleMessage: A sample message
    """
    # create a sample message
    sample_message = SampleMessage(
        name="python",
        tags=["foo", "bar"],
    )

    # add a sub message
    sub = sample_message.subs.add()
    sub.flag = True
    sub.value = 42.1984

    sub = sample_message.subs.add()
    sub.flag = False
    sub.value = -42.1984

    sample_message.meta.flag = True
    sample_message.meta.value = 42.1984

    sample_message.time.FromDatetime(datetime.now())
    sample_message.duration.FromTimedelta(timedelta(days=1))

    return sample_message
