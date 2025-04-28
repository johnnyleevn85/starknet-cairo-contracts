import pytest


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

    app_governor = bascule_test_context["contracts_by_role"]["app_governor"]

    invocation = await app_governor.functions["set_max_deposits"].invoke_v3(
        15,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance()

    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 15

    invocation = await app_governor.functions["set_max_deposits"].invoke_v3(
        50,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance()


@pytest.mark.asyncio
async def test_get_and_update_validation_threshold(bascule_test_context: dict):
    app_governor = bascule_test_context["contracts_by_role"]["app_governor"]
    user = bascule_test_context["contracts_by_role"]["user"]

    # Check default threshold (should be 0)
    (threshold,) = await user.functions["get_validation_threshold"].call()
    assert threshold == 0

    # Update the threshold
    invocation = await app_governor.functions["update_validation_threshold"].invoke_v3(
        100, auto_estimate=True
    )
    await invocation.wait_for_acceptance()

    (new_threshold,) = await user.functions["get_validation_threshold"].call()
    assert new_threshold == 100

    # Clean the state
    invocation = await app_governor.functions["update_validation_threshold"].invoke_v3(
        threshold, auto_estimate=True
    )


@pytest.mark.asyncio
async def test_update_threshold_rejects_unauthorized(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]

    with pytest.raises(Exception, match="ONLY_APP_GOVERNOR"):
        await user.functions["update_validation_threshold"].invoke_v3(42, auto_estimate=True)


@pytest.mark.asyncio
async def test_report_deposits_and_check_status(bascule_test_context: dict):
    operator = bascule_test_context["contracts_by_role"]["operator"]
    user = bascule_test_context["contracts_by_role"]["user"]

    # Make random deposit IDs
    deposit_ids = [1000, 2000, 3000]
    report_id = 5000

    # Check default status (should be Unreported)
    for deposit_id in deposit_ids:
        (status,) = await operator.functions["get_deposit_status"].call(deposit_id)
        assert status.as_dict()["variant"] == "Unreported"

    with pytest.raises(Exception, match="ONLY_OPERATOR"):
        await user.functions["report_deposits"].invoke_v3(
            report_id, deposit_ids, auto_estimate=True
        )
        await user.functions["update_validation_threshold"].invoke_v3(42, auto_estimate=True)

    # Report deposits
    invocation = await operator.functions["report_deposits"].invoke_v3(
        report_id, deposit_ids, auto_estimate=True
    )
    await invocation.wait_for_acceptance()

    for deposit_id in deposit_ids:
        (status,) = await operator.functions["get_deposit_status"].call(deposit_id)
        assert status.as_dict()["variant"] == "Reported"


@pytest.mark.asyncio
async def test_validate_withdrawal(bascule_test_context: dict):
    operator = bascule_test_context["contracts_by_role"]["operator"]
    validation_consumer = bascule_test_context["contracts_by_role"]["validation_consumer"]

    deposit_id = 20_000
    report_id = 4_000

    # Report deposit
    await (
        await operator.functions["report_deposits"].invoke_v3(
            report_id, [deposit_id], auto_estimate=True
        )
    ).wait_for_acceptance()

    # Validate withdrawal
    invocation = await validation_consumer.functions["validate_withdrawal"].invoke_v3(
        deposit_id, 100, auto_estimate=True
    )
    await invocation.wait_for_acceptance()

    # Check that it's marked as withdrawn
    (status,) = await validation_consumer.functions["get_deposit_status"].call(deposit_id)
    assert status.as_dict()["variant"] == "Withdrawn"
