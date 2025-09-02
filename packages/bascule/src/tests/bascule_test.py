import pytest
from test_utils.starknet_test_utils import get_cairo_int_constant
from pathlib import Path


@pytest.mark.asyncio
async def test_get_max_deposits(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 50


@pytest.mark.asyncio
async def test_set_max_deposits(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]
    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 50

    governance_admin = bascule_test_context["contracts_by_role"]["governance_admin"]

    invocation = await governance_admin.functions["set_max_deposits"].invoke_v3(
        15,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance(check_interval=0.1)

    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 15

    invocation = await governance_admin.functions["set_max_deposits"].invoke_v3(
        50,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance(check_interval=0.1)


@pytest.mark.asyncio
async def test_get_and_update_validation_threshold(bascule_test_context: dict):
    governance_admin = bascule_test_context["contracts_by_role"]["governance_admin"]
    user = bascule_test_context["contracts_by_role"]["user"]

    # Check default threshold (should be 0)
    (threshold,) = await user.functions["get_validation_threshold"].call()
    assert threshold == 0

    # Update the threshold
    invocation = await governance_admin.functions["update_validation_threshold"].invoke_v3(
        100, auto_estimate=True
    )
    await invocation.wait_for_acceptance(check_interval=0.1)

    (new_threshold,) = await user.functions["get_validation_threshold"].call()
    assert new_threshold == 100

    # Clean the state
    invocation = await governance_admin.functions["update_validation_threshold"].invoke_v3(
        threshold, auto_estimate=True
    )


@pytest.mark.asyncio
async def test_update_threshold_rejects_unauthorized(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]

    with pytest.raises(Exception, match="Caller is missing role"):
        await user.functions["update_validation_threshold"].invoke_v3(42, auto_estimate=True)


@pytest.mark.asyncio
async def test_report_deposits_and_check_status(bascule_test_context: dict):
    deposit_reporter = bascule_test_context["contracts_by_role"]["deposit_reporter"]
    user = bascule_test_context["contracts_by_role"]["user"]

    # Make random deposit IDs
    deposit_ids = [1000, 2000, 3000]
    report_id = 5000

    # Check default status (should be Unreported)
    for deposit_id in deposit_ids:
        (status,) = await deposit_reporter.functions["get_deposit_status"].call(deposit_id)
        assert status.as_dict()["variant"] == "Unreported"

    with pytest.raises(Exception, match="Caller is missing role"):
        await user.functions["report_deposits"].invoke_v3(
            report_id, deposit_ids, auto_estimate=True
        )

    # Report deposits
    invocation = await deposit_reporter.functions["report_deposits"].invoke_v3(
        report_id, deposit_ids, auto_estimate=True
    )
    await invocation.wait_for_acceptance(check_interval=0.1)

    for deposit_id in deposit_ids:
        (status,) = await deposit_reporter.functions["get_deposit_status"].call(deposit_id)
        assert status.as_dict()["variant"] == "Reported"


@pytest.mark.asyncio
async def test_validate_withdrawal(bascule_test_context: dict):
    withdrawal_validator = bascule_test_context["contracts_by_role"]["withdrawal_validator"]
    deposit_reporter = bascule_test_context["contracts_by_role"]["deposit_reporter"]

    bascule_path = (
        Path(__file__).parent.parent.parent.parent / "testing" / "src" / "utils" / "bascule.cairo"
    )
    to_chain = get_cairo_int_constant(bascule_path, "TO_CHAIN")
    recipient = get_cairo_int_constant(bascule_path, "RECIPIENT")
    withdrawal_amount = get_cairo_int_constant(bascule_path, "WITHDRAWAL_AMOUNT")
    tx_id = get_cairo_int_constant(bascule_path, "TX_ID")
    vout = get_cairo_int_constant(bascule_path, "VOUT")

    deposit_id = get_cairo_int_constant(bascule_path, "DEPOSIT_ID")
    report_id = 4_000

    # Report deposit
    await (
        await deposit_reporter.functions["report_deposits"].invoke_v3(
            report_id, [deposit_id], auto_estimate=True
        )
    ).wait_for_acceptance(check_interval=0.1)

    # Validate withdrawal
    invocation = await withdrawal_validator.functions["validate_withdrawal"].invoke_v3(
        to_chain, recipient, withdrawal_amount, tx_id, vout, auto_estimate=True
    )
    await invocation.wait_for_acceptance(check_interval=0.1)

    # Check that it's marked as withdrawn
    (status,) = await deposit_reporter.functions["get_deposit_status"].call(deposit_id)
    assert status.as_dict()["variant"] == "Withdrawn"
