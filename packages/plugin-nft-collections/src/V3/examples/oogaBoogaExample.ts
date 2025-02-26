import { PluginManager } from '../services/PluginManager';
import { OogaBoogaPlugin } from '../plugins/OogaBoogaPlugin';

async function main() {
  // Initialize plugin manager
  const pluginManager = new PluginManager();
  
  // Register Ooga Booga plugin
  const oogaBoogaPlugin = new OogaBoogaPlugin();
  pluginManager.registerPlugin('oogabooga', oogaBoogaPlugin);
  
  // Initialize plugins
  await pluginManager.initializePlugins();
  
  // Get collections from Ooga Booga
  const collections = await oogaBoogaPlugin.getCollections();
  console.log('Available collections:', collections);
  
  // Get floor price for a specific collection
  if (collections.length > 0) {
    const collectionId = collections[0].id;
    const floorPrice = await oogaBoogaPlugin.getFloorPrice(collectionId);
    console.log(`Floor price for collection ${collectionId}: ${floorPrice}`);
    
    // Execute a trade if floor price is below threshold
    const targetPrice = 1.5; // Example threshold
    if (floorPrice < targetPrice) {
      const tradeParams = {
        collectionId,
        action: 'buy',
        quantity: 1,
        maxPrice: targetPrice,
        size: SAFETY_LIMITS.MAX_POSITION_SIZE * 0.5 // 50% of max position size
      };
      
      try {
        const tradeResult = await oogaBoogaPlugin.executeTrade(tradeParams);
        console.log('Trade executed successfully:', tradeResult);
      } catch (error) {
        console.error('Trade execution failed:', error);
      }
    }
  }
}

main().catch(console.error); 