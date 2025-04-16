import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_current_epoch(consortium_test_context: dict):
    user = consortium_test_context["contracts_by_role"]["user_1"]

    (res,) = await user.functions["get_current_epoch"].call()
    assert res == 0
    app_governor = consortium_test_context["contracts_by_role"]["app_governor"]
    await (
        await app_governor.functions["set_initial_validator_set"].invoke_v3(
            validators=[
                (
                    0x6E145CCEF1033DEA239875DD00DFB4FEE6E3348B84985C92F103444683BAE07B,
                    0x83B5C38E5E2B0C8529D7FA3F64D46DAA1ECE2D9AC14CAB9477D042C84C32CCD0,
                )
            ],
            weights=[1],
            threshold_weight=1,
            auto_estimate=True,
        )
    ).wait_for_acceptance()

    (res,) = await user.functions["get_current_epoch"].call()
    assert res == 1
