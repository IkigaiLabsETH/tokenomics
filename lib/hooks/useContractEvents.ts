import { useEffect } from 'react';
import { useContractEvent } from 'wagmi';

export function useRewardEvents(address: string) {
  useContractEvent({
    address: REWARDS_CONTRACT,
    abi: REWARDS_ABI,
    eventName: 'RewardPaid',
    listener(user, amount, rewardType) {
      if (user === address) {
        // Update UI
      }
    },
  });

  useContractEvent({
    address: NFT_CONTRACT,
    abi: NFT_ABI,
    eventName: 'EcosystemMint',
    listener(user, collection, tokenId, discount) {
      if (user === address) {
        // Update UI
      }
    },
  });
} 