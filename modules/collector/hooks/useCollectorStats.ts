import { useState, useEffect } from 'react';
import { useContractReads } from 'wagmi';
import { REWARDS_ABI, NFT_ABI } from '@/common/constants/abis';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-ui';

export const useCollectorStats = (address: string) => {
  const [stats, setStats] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const reservoirClient = useReservoirClient();

  // Contract reads configuration
  const contracts = {
    rewards: {
      address: REWARDS_CONTRACT,
      abi: REWARDS_ABI,
    },
    nft: {
      address: NFT_CONTRACT,
      abi: NFT_ABI,
    }
  };

  // Fetch on-chain data
  const { data: contractData } = useContractReads({
    contracts: [
      {
        ...contracts.rewards,
        functionName: 'getUserTradingStats',
        args: [address],
      },
      {
        ...contracts.nft,
        functionName: 'getStakingInfo',
        args: [address],
      },
      {
        ...contracts.nft,
        functionName: 'getUserEcosystemTiers',
        args: [address],
      }
    ],
  });

  // Fetch Reservoir data
  useEffect(() => {
    const fetchReservoirData = async () => {
      try {
        const [userActivity, nftHoldings] = await Promise.all([
          reservoirClient.actions.getUserActivity({ user: address }),
          reservoirClient.actions.getUserTokens({ user: address })
        ]);

        // Combine all data
        setStats({
          tradingVolume: contractData?.[0]?.volume || 0,
          comboStreak: contractData?.[0]?.streak || 0,
          stakingInfo: contractData?.[1] || {},
          ecosystemTiers: contractData?.[2] || [],
          recentActivity: userActivity,
          nftHoldings: nftHoldings
        });
      } catch (error) {
        console.error('Error fetching collector stats:', error);
      } finally {
        setIsLoading(false);
      }
    };

    if (address) {
      fetchReservoirData();
    }
  }, [address, contractData, reservoirClient]);

  return { stats, isLoading };
}; 