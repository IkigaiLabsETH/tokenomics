import { PluginInterface } from "../interfaces/PluginInterface";

export class PluginManager {
  private plugins: Map<string, PluginInterface> = new Map();
  
  async registerPlugin(plugin: PluginInterface): Promise<boolean> {
    const name = plugin.getName();
    
    if (this.plugins.has(name)) {
      console.warn(`Plugin ${name} is already registered`);
      return false;
    }
    
    const initialized = await plugin.initialize();
    if (initialized) {
      this.plugins.set(name, plugin);
      console.log(`Plugin ${name} v${plugin.getVersion()} registered successfully`);
      return true;
    } else {
      console.error(`Failed to initialize plugin ${name}`);
      return false;
    }
  }
  
  async unregisterPlugin(name: string): Promise<boolean> {
    const plugin = this.plugins.get(name);
    
    if (!plugin) {
      console.warn(`Plugin ${name} is not registered`);
      return false;
    }
    
    await plugin.shutdown();
    this.plugins.delete(name);
    console.log(`Plugin ${name} unregistered successfully`);
    return true;
  }
  
  getPlugin<T extends PluginInterface>(name: string): T | null {
    const plugin = this.plugins.get(name);
    return plugin as T || null;
  }
  
  listPlugins(): string[] {
    return Array.from(this.plugins.keys());
  }
  
  async shutdownAll(): Promise<void> {
    for (const [name, plugin] of this.plugins.entries()) {
      await plugin.shutdown();
      console.log(`Plugin ${name} shut down`);
    }
    this.plugins.clear();
  }
} 