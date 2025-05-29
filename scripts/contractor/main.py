import asyncio

from src.contractor import change_treasury
from src.test import transfer


if __name__ ==  '__main__':
    loop = asyncio.new_event_loop()
    # loop.run_until_complete(change_treasury())
    loop.run_until_complete(transfer())
