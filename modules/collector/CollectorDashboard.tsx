import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import { formatEther } from 'ethers/lib/utils';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-ui';
import { useThirdwebClient } from '@thirdweb-dev/react';
import { StatsCard } from '@/common/components/StatsCard';
import { NFTGrid } from '@/common/components/NFTGrid';
import { useCollectorStats } from './hooks/useCollectorStats';

export const CollectorDashboard = () => {
  const { address } = useAccount();
  const { stats, isLoading } = useCollectorStats(address);
  const reservoirClient = useReservoirClient();

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        {/* Trading Stats */}
        <StatsCard
          title="Trading Activity"
          isLoading={isLoading}
          items={[
            {
              label: "Volume",
              value: stats?.tradingVolume ? `${formatEther(stats.tradingVolume)} BERA` : '-',
              change: stats?.volumeChange
            },
            {
              label: "Combo Streak", 
              value: stats?.comboStreak || 0,
              highlight: stats?.comboStreak > 5
            }
          ]}
        />

        {/* Staking Stats */}
        <StatsCard
          title="Staking Status"
          isLoading={isLoading} 
          items={[
            {
              label: "Staked",
              value: stats?.stakedAmount ? `${formatEther(stats.stakedAmount)} IKIGAI` : '-'
            },
            {
              label: "Tier",
              value: `Level ${stats?.stakingTier || 1}`,
              highlight: stats?.stakingTier > 2
            }
          ]}
        />

        {/* Rewards Stats */}
        <StatsCard
          title="Rewards"
          isLoading={isLoading}
          items={[
            {
              label: "Pending",
              value: stats?.pendingRewards ? `${formatEther(stats.pendingRewards)} IKIGAI` : '-'
            },
            {
              label: "Next Claim",
              value: stats?.nextClaimTime ? formatTimeLeft(stats.nextClaimTime) : '-'
            }
          ]}
        />
      </div>

      {/* NFT Holdings */}
      <div className="mb-8">
        <h2 className="text-2xl font-bold mb-4">Your NFT Holdings</h2>
        <NFTGrid
          tokens={stats?.nftHoldings || []}
          loading={isLoading}
          emptyText="No NFTs found"
        />
      </div>

      {/* Available Benefits */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-xl font-semibold mb-4">Minting Benefits</h3>
          <div className="space-y-4">
            {stats?.availableDiscounts.map((discount, i) => (
              <div key={i} className="flex justify-between items-center">
                <span className="text-gray-600">{discount.type}</span>
                <span className="font-medium text-green-600">
                  {discount.amount}% off
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-xl font-semibold mb-4">Ecosystem Status</h3>
          <div className="space-y-4">
            {stats?.ecosystemNFTs.map((nft, i) => (
              <div key={i} className="flex justify-between items-center">
                <span className="text-gray-600">{nft.collection}</span>
                <span className="font-medium">
                  Tier {nft.tier} ({nft.discount}% discount)
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}; 