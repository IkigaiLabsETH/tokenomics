import { useState } from 'react';
import { useContractWrite } from 'wagmi';
import { AdminTabs } from './components/AdminTabs';
import { EcosystemPanel } from './components/EcosystemPanel';
import { RewardsPanel } from './components/RewardsPanel';
import { FeesPanel } from './components/FeesPanel';
import { EmergencyPanel } from './components/EmergencyPanel';

export const AdminPanel = () => {
  const [activeTab, setActiveTab] = useState('ecosystem');

  return (
    <div className="container mx-auto px-4 py-8">
      <AdminTabs activeTab={activeTab} onChange={setActiveTab} />
      
      <div className="mt-8">
        {activeTab === 'ecosystem' && <EcosystemPanel />}
        {activeTab === 'rewards' && <RewardsPanel />}
        {activeTab === 'fees' && <FeesPanel />}
        {activeTab === 'emergency' && <EmergencyPanel />}
      </div>
    </div>
  );
}; 