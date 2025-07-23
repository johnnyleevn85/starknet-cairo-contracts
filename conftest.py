import pytest
from starknet_test_util import StarknetTestUtils
from typing import Iterator
import time


@pytest.fixture(scope="function")
def starknet_test_utils() -> Iterator[StarknetTestUtils]:
    with StarknetTestUtils.context_manager() as val:
        # TODO: replace the sleep with await.
        time.sleep(2)
        yield val
