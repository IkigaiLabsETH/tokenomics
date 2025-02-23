import { useState, useEffect } from 'react';
import { useContractReads } from 'wagmi';
import { REWARDS_ABI, NFT_ABI } from '@/common/constants/abis';
import { CONTRACTS } from '@/common/constants/contracts';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-ui'; 