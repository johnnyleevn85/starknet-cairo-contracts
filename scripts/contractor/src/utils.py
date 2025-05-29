from typing import Optional
from starknet_py.contract import PreparedFunctionInvokeV3
from starknet_py.net.client_models import EstimatedFee, ResourceBoundsMapping
from starknet_py.net.models.transaction import InvokeV3

async def sign(
    invoke: PreparedFunctionInvokeV3,
    resource_bounds: Optional[ResourceBoundsMapping] = None,
    auto_estimate: bool = False,
    *,
    nonce: Optional[int] = None,
) -> InvokeV3:

    if not resource_bounds:
        account = invoke.get_account
        tx = await account.sign_invoke_v3(
            calls=invoke,
            nonce=nonce,
            resource_bounds=ResourceBoundsMapping.init_with_zeros(),
        )
        estimate_tx = await account.sign_for_fee_estimate(transaction=tx)
        estimated_fee = await account.estimate_fee(estimate_tx, skip_validate=True)
        assert isinstance(estimated_fee, EstimatedFee)
        resource_bounds = estimated_fee.to_resource_bounds()

    return await invoke.get_account.sign_invoke_v3(
        calls=invoke,
        nonce=nonce,
        resource_bounds=resource_bounds or invoke.resource_bounds,
        auto_estimate=auto_estimate,
    )
