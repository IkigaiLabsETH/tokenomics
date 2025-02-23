import { useState, useEffect } from 'react';
import { useContractReads } from 'wagmi';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-client';
import { CONTRACTS } from '@/config/contracts';
import { ABIS } from '@/config/abis';

export const useCollectorStats = (address: string) => {
  const [stats, setStats] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const reservoirClient = useReservoirClient();

  const { data: contractData } = useContractReads({
    contracts: [
      {
        address: CONTRACTS.REWARDS,
        abi: ABIS.REWARDS,
        functionName: 'getUserTradingStats',
        args: [address],
      },
      {
        address: CONTRACTS.NFT,
        abi: ABIS.NFT,
        functionName: 'getStakingInfo',
        args: [address],
      }
    ],
  });

  useEffect(() => {
    const fetchReservoirData = async () => {
      try {
        const [userActivity, nftHoldings] = await Promise.all([
          reservoirClient.actions.getUserActivity({ user: address }),
          reservoirClient.actions.getUserTokens({ user: address })
        ]);

        setStats({
          tradingVolume: contractData?.[0]?.volume || 0,
          comboStreak: contractData?.[0]?.streak || 0,
          stakingInfo: contractData?.[1] || {},
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