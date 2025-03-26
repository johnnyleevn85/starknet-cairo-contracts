import pytest
from test_utils import StarknetTestUtils


@pytest.fixture(scope="session")
def starknet_test_utils() -> StarknetTestUtils:
    with StarknetTestUtils.context_manager() as val:
        yield val
