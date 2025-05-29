import requests
from starknet_py.net.account.account import Account
from starknet_py.net.client_models import ResourceBounds, ResourceBoundsMapping
from starknet_py.contract import Contract
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.models.chains import StarknetChainId, parse_chain
from starknet_py.net.signer.key_pair import KeyPair
from starknet_py.net.signer.stark_curve_signer import StarkCurveSigner

from src.utils import sign


MAINNET_URL = 'https://starknet-mainnet.public.blastapi.io'
TESTNET_URL = 'https://starknet-sepolia.public.blastapi.io/rpc/v0_8'

MULTISIG_PRIVATE_KEY = '0x0114fc83b2441cd456774f37ae35a3760464ca3f84a37828a64ca9cc94b007b7'
MULTISIG_PUBLIC_KEY = '0x00bddf625fcfb426762bc8cceaeb006304fbe6af8adb0a3d2bbd0f77b256014b'
MULTISIG_ADDRESS = '0x001afebfe9bd3ca1e3315e1b53d92040230c2361ae6848c3046a4eb13c5bff26'

BRIDGE_CONTRACT_ADDRESS = '0x0701e8454ea75a1186638672115b29e7b63e2a4c62ce53008b2d3bd74e229c07'

TREASURY_ADDRESS = '0x02551b1f37dAD720a72ABeFc954428a045715817d21642dc12DD92605dA9E63a'

ARGENT_TESTNET_URL = 'https://cloud.argent-api.com/v1/multisig/starknet/sepolia/'


async def change_treasury():
    client = FullNodeClient(node_url=TESTNET_URL)

    key_pair = KeyPair.from_private_key(key=MULTISIG_PRIVATE_KEY)

    signer = StarkCurveSigner(MULTISIG_PUBLIC_KEY, key_pair, parse_chain(StarknetChainId.SEPOLIA))

    account = Account(
        client=client, address=MULTISIG_ADDRESS, signer=signer, chain=StarknetChainId.SEPOLIA
    )
    # bridge_contract = Contract(
    #     address=BRIDGE_CONTRACT_ADDRESS,
    #     abi=,
    #     provider=account,
    #     cairo_version=1,
    # )
    bridge_contract = await Contract.from_address(provider=account, address=BRIDGE_CONTRACT_ADDRESS)

    nonce = await account.get_nonce(block_number="pending")

    # resource_bounds=ResourceBoundsMapping(
    #     l1_gas=ResourceBounds(max_amount=int(1e5), max_price_per_unit=int(1e13)),
    #     l2_gas=ResourceBounds(max_amount=int(1e10), max_price_per_unit=int(1e17)),
    #     l1_data_gas=ResourceBounds(
    #         max_amount=int(1e5), max_price_per_unit=int(1e13)
    #     ),
    # )

    invokation = bridge_contract.functions["change_treasury"].prepare_invoke_v3(
        int(TREASURY_ADDRESS, 16),
        # resource_bounds=resource_bounds,
    )

    transaction = await sign(invoke=invokation, auto_estimate=False, nonce=nonce, resource_bounds=None)

    [r,s] = transaction.signature

    tx_hash = hex(transaction.calculate_hash(signer.chain_id))
    print("tx hash: " + tx_hash)

    # curl 'https://cloud.argent-api.com/v1/multisig/starknet/sepolia/0x001afebfe9bd3ca1e3315e1b53d92040230c2361ae6848c3046a4eb13c5bff26/request' -X POST -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:138.0) Gecko/20100101 Firefox/138.0' -H 'Accept: application/json' -H 'Accept-Language: en' -H 'Accept-Encoding: gzip, deflate, br, zstd' -H 'Content-Type: application/json' -H 'argent-version: 5.24.2' -H 'argent-client: argent-x' -H 'Origin: moz-extension://763911f5-b7d0-4a88-a9bc-b9be3240f961' -H 'Connection: keep-alive' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-origin' -H 'Priority: u=4' -H 'TE: trailers' --data-raw '{"creator":"0x00bddf625fcfb426762bc8cceaeb006304fbe6af8adb0a3d2bbd0f77b256014b","transaction":{"maxFee":"0x0","nonce":"0x2","version":"0x3","calls":[{"contractAddress":"0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d","calldata":["278462223880509967929621306023085600642201983486554849709157872985035362188","1000000000000000000","0"],"entrypoint":"transfer"}],"resource_bounds":{"l1_gas":{"max_amount":"0x2c","max_price_per_unit":"0x1b697ea7ddaf2f"},"l2_gas":{"max_amount":"0x0","max_price_per_unit":"0x0"}}},"starknetSignature":{"r":"0x4c7376e7b96c2b84e093c7e04ded80415792ac7570973a760a2fd4db32d0686","s":"0x178f694e484ba27804ea34b943ee1785f52b3d52e631aadda266b216a5e34c2"}}'
    payload = {
        "creator": MULTISIG_PUBLIC_KEY,
        "transaction": {
            "nonce": hex(transaction.nonce),
            "version": hex(transaction.version),
            "maxFee": "0x0",
            "calls": [
                {
                    "contractAddress": BRIDGE_CONTRACT_ADDRESS,
                    "calldata": transaction.calldata[3:],
                    "entrypoint": "change_treasury",
                }
            ],
            "resource_bounds": {
                "l1_gas": {
                    "max_amount": hex(transaction.resource_bounds.l1_gas.max_amount),
                    "max_price_per_unit": hex(transaction.resource_bounds.l1_gas.max_price_per_unit),
                },
                "l2_gas": {
                    "max_amount": hex(transaction.resource_bounds.l2_gas.max_amount),
                    "max_price_per_unit": hex(transaction.resource_bounds.l2_gas.max_price_per_unit),
                },
                "l1_data_gas": {
                    "max_amount": hex(transaction.resource_bounds.l1_data_gas.max_amount),
                    "max_price_per_unit": hex(transaction.resource_bounds.l1_data_gas.max_price_per_unit),
                }
            },
        },
        "starknetSignature": {
            "r": hex(r),
            "s": hex(s),
        },
    }

    for i, data in enumerate(payload["transaction"]["calls"][0]["calldata"]):
        payload["transaction"]["calls"][0]["calldata"][i] = str(data)

    argent_url = f"{ARGENT_TESTNET_URL}{MULTISIG_ADDRESS}/request"
    response = requests.post(argent_url, json=payload)
    response.raise_for_status()
