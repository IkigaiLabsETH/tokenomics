import { useState, useEffect } from 'react';
import { useContractReads } from 'wagmi';
import { REWARDS_ABI, NFT_ABI } from '../../../common/constants/abis';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-ui';
// ... rest of the code remains the same 