import { PluginInterface } from '../interfaces/PluginInterface';
import { OogaBoogaService } from '../services/oogabooga/OogaBoogaService';

export class OogaBoogaPlugin implements PluginInterface {
  private service: OogaBoogaService;
  
  constructor() {
    this.service = new OogaBoogaService();
  }
  
  async initialize(): Promise<void> {
    await this.service.initialize();
  }
  
  async getCollections(): Promise<any[]> {
    return this.service.getCollections();
  }
  
  async getFloorPrice(collectionId: string): Promise<number> {
    return this.service.getFloorPrice(collectionId);
  }
  
  async executeTrade(params: any): Promise<any> {
    return this.service.executeTrade(params);
  }
  
  // Implement other required methods from PluginInterface
} 