import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_current_epoch(consortium_test_context: dict):
    user = consortium_test_context["contracts_by_role"]["user_1"]

    (res,) = await user.functions["get_current_epoch"].call()
    assert res == 0
    app_governor = consortium_test_context["contracts_by_role"]["app_governor"]
    # TODO(ROEEG)
    # await (
    #     await app_governor.functions["set_initial_validator_set"].invoke_v3(
    #         [
    #             {
    #                 "public_key": (
    #                     0x21A30C0BDAA3B425E17A062BFDF5B8ECAED4E2D3AB4B30B0774472D4621081D9,
    #                     0x6A50131029F32EFFBE5D8BA0DA8C75760FF5ADD90C77EFCD48EEEBBF56094BD8,
    #                 )
    #             }
    #         ],
    #         [1],
    #         1,
    #         auto_estimate=True,
    #     )
    # ).wait_for_acceptance()

    # (res,) = await user.functions["get_current_epoch"].call()
    # assert res == 1
