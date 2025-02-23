import { useAccount } from 'wagmi';
import { formatEther } from 'ethers/lib/utils';
import { useReservoirClient } from '@reservoir0x/reservoir-kit-client';
import { Card } from '@/components/ui/Card';
import { TokenGrid } from '@/components/ui/TokenGrid';
import { useCollectorStats } from '@/hooks/useCollectorStats';

export function CollectorDashboard() {
  const { address } = useAccount();
  const { stats, isLoading } = useCollectorStats(address);

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <Card
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
        
        <Card
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
      </div>

      <TokenGrid 
        tokens={stats?.nftHoldings || []}
        loading={isLoading}
        emptyText="No NFTs found"
      />
    </div>
  );
} 