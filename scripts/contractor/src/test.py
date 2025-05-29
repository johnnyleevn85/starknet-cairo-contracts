import requests
from starknet_py.net.account.account import Account
from starknet_py.contract import Contract
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.models.chains import StarknetChainId, parse_chain
from starknet_py.net.signer.key_pair import KeyPair
from starknet_py.net.signer.stark_curve_signer import StarkCurveSigner

from src.utils import sign


MAINNET_URL = 'https://starknet-mainnet.public.blastapi.io'
TESTNET_URL = 'https://starknet-sepolia.public.blastapi.io/rpc/v0_8'

# PRIVATE_KEY = '0x05469bf05221c5f74b9edd7cfc9ef04848171879bd051cf2a9db5d7124b078fe'
# PUBLIC_KEY = '0x05a3fcd073544f2d0f2623dcd90d99b037863f7a2f1fc7a3a47188383baead7e'
# ADDRESS = '0x009D9aA1ef7e08519bB9DdeE4E749cFf4F9f8B8F46143C2071E3DAbf3B3Dcf8c'
PRIVATE_KEY = '0x0114fc83b2441cd456774f37ae35a3760464ca3f84a37828a64ca9cc94b007b7'
PUBLIC_KEY = '0x00bddf625fcfb426762bc8cceaeb006304fbe6af8adb0a3d2bbd0f77b256014b'
ADDRESS = '0x001afebfe9bd3ca1e3315e1b53d92040230c2361ae6848c3046a4eb13c5bff26'
# ADDRESS = '0x00bddf625fcfb426762bc8cceaeb006304fbe6af8adb0a3d2bbd0f77b256014b'

CONTRACT_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"

TREASURY_ADDRESS = '0x02551b1f37dAD720a72ABeFc954428a045715817d21642dc12DD92605dA9E63a'

ARGENT_TESTNET_URL = 'https://cloud.argent-api.com/v1/multisig/starknet/sepolia/'


async def transfer():
    client = FullNodeClient(node_url=TESTNET_URL)

    key_pair = KeyPair.from_private_key(key=PRIVATE_KEY)

    signer = StarkCurveSigner(PUBLIC_KEY, key_pair, parse_chain(StarknetChainId.SEPOLIA))

    account = Account(
        client=client, address=ADDRESS, signer=signer, chain=StarknetChainId.SEPOLIA
    )

    # bridge_contract = Contract(
    #     address=BRIDGE_CONTRACT_ADDRESS,
    #     abi=,
    #     provider=account,
    #     cairo_version=1,
    # )
    transfer_contract = await Contract.from_address(provider=account, address=CONTRACT_ADDRESS)

    nonce = await account.get_nonce(block_number="pending")

    # resource_bounds=ResourceBoundsMapping(
    #     l1_gas=ResourceBounds(max_amount=int(1e5), max_price_per_unit=int(3*1e13)),
    #     l2_gas=ResourceBounds(max_amount=int(0), max_price_per_unit=int(0)),
    #     l1_data_gas=ResourceBounds(
    #         max_amount=0, max_price_per_unit=0
    #     ),
    # )

    invokation = transfer_contract.functions["transfer"].prepare_invoke_v3(
        int("0x02551b1f37dAD720a72ABeFc954428a045715817d21642dc12DD92605dA9E63a", 16), 1000000000000000000,
    )

    transaction = await sign(invoke=invokation, auto_estimate=False, nonce=nonce)

    [r,s] = transaction.signature

    tx_hash = hex(transaction.calculate_hash(signer.chain_id))
    print("tx hash: " + tx_hash)

    # result = await client.send_transaction(transaction=transaction)

    # print("tx send result: " + hex(result.transaction_hash))

    # curl 'https://cloud.argent-api.com/v1/multisig/starknet/sepolia/0x001afebfe9bd3ca1e3315e1b53d92040230c2361ae6848c3046a4eb13c5bff26/request' -X POST -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:138.0) Gecko/20100101 Firefox/138.0' -H 'Accept: application/json' -H 'Accept-Language: en' -H 'Accept-Encoding: gzip, deflate, br, zstd' -H 'Content-Type: application/json' -H 'argent-version: 5.24.2' -H 'argent-client: argent-x' -H 'Origin: moz-extension://763911f5-b7d0-4a88-a9bc-b9be3240f961' -H 'Connection: keep-alive' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: same-origin' -H 'Priority: u=4' -H 'TE: trailers' --data-raw '{"creator":"0x00bddf625fcfb426762bc8cceaeb006304fbe6af8adb0a3d2bbd0f77b256014b","transaction":{"maxFee":"0x0","nonce":"0x2","version":"0x3","calls":[{"contractAddress":"0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d","calldata":["278462223880509967929621306023085600642201983486554849709157872985035362188","1000000000000000000","0"],"entrypoint":"transfer"}],"resource_bounds":{"l1_gas":{"max_amount":"0x2c","max_price_per_unit":"0x1b697ea7ddaf2f"},"l2_gas":{"max_amount":"0x0","max_price_per_unit":"0x0"}}},"starknetSignature":{"r":"0x4c7376e7b96c2b84e093c7e04ded80415792ac7570973a760a2fd4db32d0686","s":"0x178f694e484ba27804ea34b943ee1785f52b3d52e631aadda266b216a5e34c2"}}'
    payload = {
        "creator": PUBLIC_KEY,
        "transaction": {
            "nonce": hex(transaction.nonce),
            "version": hex(transaction.version),
            "maxFee": "0x0",
            "calls": [
                {
                    "contractAddress": CONTRACT_ADDRESS,
                    "calldata": transaction.calldata[4:],
                    "entrypoint": "transfer",
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

    argent_url = f"{ARGENT_TESTNET_URL}{ADDRESS}/request"
    response = requests.post(argent_url, json=payload)
    response.raise_for_status()
