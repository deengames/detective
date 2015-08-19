require 'scripts/logger'
require 'scripts/npc_spawner'
require 'scripts/ui/profiles_scene'
require 'scripts/models/notebook'
require 'scripts/api/vxace_api'

class DetectiveGame

  # TODO: this is updated by hand :(
  # These are the names of ITEMS in the DB.
  POTENTIAL_MURDER_WEAPONS = ['Sword', 'Pickaxe', 'Vase', 'Pot', 'Shovel']

  # The key for storing this game's data in our save-game.
  DATA_KEY = :detective_game
  attr_reader :npcs, :notebook

  @@instance = nil
  
  def self.instance
    @@instance = DataManager.get(DATA_KEY) || DetectiveGame.new    
    return @@instance
  end
  
  def initialize(num_npcs = 6)        
    raise "Need an even number of people for this scenario" if num_npcs % 2 == 1
    generate_npcs(num_npcs)
    pick_murder_weapon
    @notebook = Notebook.new(@npcs)
    DataManager.set(DATA_KEY, self)
  end
  
  # Changes the close-up image of the murder weapon to the blood-streaked one
  def got_magnifying_glass
    for item in $data_items do
      next if item.nil?
      if item.name == @murder_weapon
        murder_item = item 
        break
      end
    end
    
    raise "Can't find item named #{@murder_weapon} for murder weapon" if murder_item.nil?
    # change big picture in inventory for this item to the blood-splattered one
    murder_item.image = "inventory\\#{murder_item.name}-blood"
  end
  
  def show_suspects_choice
    choice = Game_Interpreter.instance.show_choices(['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight'])
    Logger.log("CHOSE: #{choice}")
  end  
  
  private  
  
  def pick_murder_weapon
    @murder_weapon = POTENTIAL_MURDER_WEAPONS.sample
    Logger.log("Murder weapon: #{@murder_weapon}")
  end
  
  
  def generate_npcs(num_npcs)
    @npcs = []
    
    num_npcs.times do
      @npcs << NpcSpawner::create_npc
    end
    
    @killer = @npcs.sample
    @victim = @killer
    @victim = npcs.sample while @victim == @killer
    @victim.die

    Logger.log "Killer: #{@killer.name}"
    Logger.log "Victim: #{@victim.name}"
    
    non_victims = @npcs - [@victim]
    non_killers = non_victims - [@killer]
        
    non_killers.shuffle!    
    @killer.alibi_person = non_killers.sample
    
    # Pick two random people and link their alibis
    while non_killers.size > 0 do
      n1 = non_killers.pop
      n2 = non_killers.pop      
      n1.alibi_person = n2
      n2.alibi_person = n1
    end
  end
  
  private
  
end