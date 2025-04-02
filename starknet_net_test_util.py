import contextlib
import logging
import os
import signal
import subprocess
import tempfile
from starknet_py.net.account.account import Account
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.signer.key_pair import KeyPair
from starknet_py.net.signer.stark_curve_signer import StarkCurveSigner
import requests


from pathlib import Path

logger = logging.getLogger(__name__)

SIERRA_PROGRAM_KEY = "sierra_program"
SIERRA_KEY = "sierra"
CASM_KEY = "casm"
ABI_KEY = "abi"


def get_contract_path(contract_name: str) -> Path:
    return Path(os.path.join(os.path.dirname(__file__), "target", "dev", f"{contract_name}.json"))


def load_contract(contract_name: str) -> str:
    contract_path = get_contract_path(contract_name)
    return contract_path.read_text("utf-8")


# Due to the fixed seed, the starknet devnet will always start with the same state.
ETH_Address = 0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7
Class_Hash = 0x46DED64AE2DEAD6448E247234BAB192A9C483644395B66F2155F2614E5804B0
STRK_Address = 0x4718F5A0FC34CC1AF16A1CDEE98FFB20C31F5CD61D6AB07201858F4287C938D
Class_Hash = 0x46DED64AE2DEAD6448E247234BAB192A9C483644395B66F2155F2614E5804B0

# Predeployed UDC
UDC_Address = 0x41A78E741E5AF2FEC34B695679BC6891742439F7AFB8484ECD7766661AD02BF
UDC_Class_Hash = 0x7B3E05F48F0C69E4A65CE5E076A66271A527AFF2C34CE1083EC6E1526997A69

# Account addresses and key pairs for testing

keys = [
    "0x00000000000000000000000000000000b4fac4a807d5f17016e1b8ab17a865c4",
    "0x0000000000000000000000000000000024231a9d8f74eae8cbd8c80826c8193a",
    "0x000000000000000000000000000000001293ea7b811536b80758de00247d8183",
    "0x00000000000000000000000000000000fb49b1af8bb4c3e87701d41368f001f3",
    "0x0000000000000000000000000000000027741a991a8b3a637d0c42276f0981e7",
    "0x00000000000000000000000000000000437756c310eefe42413cf7a5ffbbe349",
    "0x000000000000000000000000000000006e54993e3de6455e0c808713dec59617",
    "0x00000000000000000000000000000000f401ceaef4f781d0a00f79a5353b6b8c",
    "0x0000000000000000000000000000000097bcc69c1f8dceeb9e4171f7d6f2c8a3",
    "0x000000000000000000000000000000009fa01c7fc02a46988a06ddaf75736838",
]
addresses = [
    "0x05b99fc6098fb3bf5a0f95cab6b7a2b6fd376bc04b2fea0ca7eb8f72216ec3b2",
    "0x063ca12081899481a94345c926661121eeab13655be408edb5c7fec854702520",
    "0x067f3fa88e047a4cc5f656423b7253bf01a2144487017fdde7f55d7a702d83d9",
    "0x02a5a18bdfd211dcc91b0145773961a72afaa39f85b3c97ab5b9d3398f658622",
    "0x0574fff23ea8c1779a7978efc0a059b6336fa4e04090118ee9aa88507c341a62",
    "0x030abb3e39b3488ec7e4381d46301cb23c4b409fa80c4fc846949ae77978d279",
    "0x077b18cd56d4ce334687bffe78123ccff4c5ea15dda013c58f17c769af39e135",
    "0x0215b7fd7d85b59c344feab99d06acbfb08d509ee4fbe87e50c304dbe074d8f0",
    "0x06eb4627dff4d0519441dd9bc05f8af2b51e21695b935a56490cbebbb985a562",
    "0x0061aa21aae0cc11130f60295c2b1157e309b0ba833d00c6b82722c11f35a748",
]


class StarknetTestUtils:
    """
    Allows testing Starknet contracts.
    """

    def __init__(self):
        self.starknet = Starknet()
        self.accounts = self.starknet.accounts

    def stop(self):
        self.starknet.stop()

    @classmethod
    @contextlib.contextmanager
    def context_manager(cls):
        res = cls()
        try:
            yield res
        finally:
            res.stop()

    def advance_time(self, n_seconds: int):
        payload = {
            "jsonrpc": "2.0",
            "id": "1",
            "method": "devnet_increaseTime",
            "params": {"time": n_seconds},
        }
        rpc_url = f"{self.starknet.get_client().url}\rpc"
        response = requests.post(rpc_url, json=payload)
        response.raise_for_status()


# call_result = await client.get_block(block_number=1)


class Starknet:
    """
    Represents a running instance of starknet.
    """

    def __init__(
        self,
        port: int = 5050,
        seed: int = 500,
        starknet_chain_id: StarknetChainId = StarknetChainId.SEPOLIA,
    ):
        """
        Runs starknet.
        Use stop() to ensure the process is killed at the end.
        """
        self.err_stream = tempfile.NamedTemporaryFile()
        self.port = port
        self.seed = seed
        self.starknet_chain_id = starknet_chain_id
        self.starknet_proc = subprocess.Popen(
            f"starknet-devnet --port {self.port} --seed {self.seed}",
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=self.err_stream,
            # Open the process in a new process group.
            start_new_session=True,
        )
        self.is_alive = True
        self.accounts = []
        key_pairs = []
        for key in keys:
            key_pairs.append(KeyPair.from_private_key(key))

        for i in range(len(addresses)):
            signer = StarkCurveSigner(addresses[i], key_pairs[i], self.starknet_chain_id)

            account = Account(
                client=self.get_client(),
                address=addresses[i],
                signer=signer,
                chain=self.starknet_chain_id,
            )
        self.accounts.append(account)

    def __del__(self):
        self.stop()

    def get_client(self) -> FullNodeClient:
        node_url = f"http://localhost:{self.port}"
        return FullNodeClient(node_url=node_url)

    def stop(self):
        if not self.is_alive:
            return

        # Kill the entire process group.
        os.killpg(self.starknet_proc.pid, signal.SIGINT)
        self.is_alive = False
        # Capture errors.
        self.err_stream.flush()
        self.err_stream.seek(0)
        stderr_data = self.err_stream.read().decode()
        if len(stderr_data) > 0:
            logger.error(f"Starknet stderr data:\n{str(stderr_data)}\n")
        self.err_stream.close()
