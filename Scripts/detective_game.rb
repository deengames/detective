require 'scripts/logger'
require 'scripts/npc_spawner'
require 'scripts/name_generator'

require 'scripts/models/notebook'
require 'scripts/models/suspect_npc'
require 'scripts/api/vxace_api'
require 'scripts/utils/external_data'
require 'scripts/evidence_generator'
require 'scripts/utils/enumerable_math'

# Not directly used here, but just load them here so that they're defined when needed.
require 'scripts/utils/json_parser'
require 'scripts/ui/profiles_scene'

#Font.default_name = ['ArabType']
#Font.default_size = 22

class DetectiveGame
  
  # Potential maps to spawn on. Names don't cut it (not accessible through the API), so we use map IDs.
  # 7-14 are House1-House8
  MANSION_MAP_ID = 1 # Mansion1
  NPC_MAPS = (7..14).to_a + [MANSION_MAP_ID]

  # The key for storing this game's data in our save-game.
  DATA_KEY = :detective_game
  attr_reader :npcs, :notebook

  @@instance = nil
  
  def self.instance
    @@instance = DataManager.get(DATA_KEY) || DetectiveGame.new  
    return @@instance
  end
  
  def initialize
    Logger.log('---------------------------------------------------')
    
    if ExternalData::instance.key?(:universe)
      seed = ExternalData::instance.get(:universe) 
    else
      srand()
      seed = srand()
    end
    srand(seed)
    Logger.log "New game started in universe ##{seed}"
        
    Logger.logging_level = :debug if ExternalData::instance.get(:debug) == true
    Logger.debug 'Logger.debug mode enabled.'
    
    difficulty = ExternalData::instance.get(:difficulty)
    raise "Difficulty (#{difficulty}) should be in the range of 1-10" if difficulty < 1 || difficulty > 10
    
    min_npcs = ExternalData::instance.get(:min_number_of_npcs)
    max_npcs = ExternalData::instance.get(:max_number_of_npcs)
    range = max_npcs - min_npcs    
    
    # map [1..10] to [0..range] (uniform distribution)
    # difficulty of 1 = min_npcs, difficulty of 10 = max_npcs    
    num_npcs = (range * difficulty / 10.0).round    
    num_npcs = rand(range) + min_npcs
    Logger.debug "Generating #{num_npcs} npcs; range was #{min_npcs} to #{max_npcs}"
    @notebook = Notebook.new
    
    @potential_murder_weapons = $data_items.collect { |i| i.name unless i.nil? }   
    @potential_murder_weapons.compact! # no nils please
    Logger.debug "Potential murder weapons (all items): #{@potential_murder_weapons}"
    generate_npcs(num_npcs)
    generate_scenario(difficulty) 
    
    @notebook.npcs = @npcs
    DataManager.set(DATA_KEY, self)    
  end
  
  def solve_case
    suspect = show_suspects_list
    if suspect != 'Cancel'
      weapon = show_murder_weapons_list
      if weapon != 'Cancel'
        if suspect == @killer.name && weapon == @murder_weapon
          Game_Interpreter.instance.show_message("#{@killer.name}: ARGH! Yes, I killed #{@victim.name} with the #{@murder_weapon}!")
        else
          Game_Interpreter.instance.show_message("#{@killer.name}: WRONG! I killed #{@victim.name} with the #{@murder_weapon}! You die!")
        end
        
        Game_Interpreter.instance.game_over
      end
    end
  end
  
  def spawn_this_maps_npcs
    @npcs.each { |n| NpcSpawner.spawn(n) if n.map_id == Game_Map::instance.map_id  }
    @evidences.each { |e| NpcSpawner.spawn(e) if e.map_id == Game_Map::instance.map_id }
  end
  
  private  
  
  def show_murder_weapons_list
    Game_Interpreter.instance.show_message('What\'s the murder weapon?', :wait => false)
    weapons_list = ['Cancel']
    @potential_murder_weapons.map { |w| weapons_list << w }
    choice = Game_Interpreter.instance.show_choices(weapons_list, { :cancel_index => 0, :return_type => :name})
    return choice
  end
  
  def show_suspects_list  
    Game_Interpreter.instance.show_message('Who\'s the killer?', :wait => false)
    npc_names = ['Cancel']
    @npcs.map { |n| npc_names << n.name }
    choice = Game_Interpreter.instance.show_choices(npc_names, { :cancel_index => 0, :return_type => :name})
    return choice
  end
  
  def generate_npcs(num_npcs)
    @npcs = []
    
    num_npcs.times do
      # Decide on a random map where this NPC appears
      map_id = NPC_MAPS.sample
      name = NameGenerator::generate_name
      @npcs << SuspectNpc.new(map_id, name)
      Logger.debug "#{@npcs[-1].name} is on map #{map_id}"
    end
  end
  
  # Signals: things that indicate that a person is the murderer
  # The number of signals is 3 + (2 * difficulty), distributed
  # randomly to NPCs. (The killer gets more signals.)
  def generate_scenario(difficulty)    
    Logger.debug "Difficulty: #{difficulty}"
    @killer = @npcs.sample
    @victim = @killer
    @victim = npcs.sample while @victim == @killer
    @victim.die
    @victim.map_id = MANSION_MAP_ID
    Logger.log "Victim: #{@victim.name}"
    Logger.debug "Killer: #{@killer.name}"
    
    non_victims = @npcs - [@victim]
    non_killers = non_victims - [@killer]       
    non_killers.shuffle!
    
    num_signals = 3 + (2 * difficulty)
    evidence_counts = {}
    generate_signals_and_profiles(num_signals, non_victims, difficulty)
    
    Logger.debug "Initial distribution: #{non_victims} v=#{non_victims.collect { |n| n.evidence_count }.variance}"
    initial_sum = 0
    non_victims.map { |n| initial_sum += n.evidence_count }
    
    non_victims.each { |n| n.augment_profile }
    @victim.evidence_count = rand(2) # 0 or 1 signal
    @victim.augment_profile
    
    # Everyone needs an alibi. Weak alibis are a signal.
    generate_killers_alibi(non_killers)
    generate_alibis(non_killers)
    
    @murder_weapon = @potential_murder_weapons.sample
    Logger.debug "Murder weapon: #{@murder_weapon}"
    
    @evidences = EvidenceGenerator::distribute_evidence(non_victims, @victim, NPC_MAPS, MANSION_MAP_ID, @notebook, @potential_murder_weapons, @murder_weapon)
    
    Logger.debug '-' * 80
    Logger.debug "Final distribution: #{non_victims}"    
    final_sum = 0
    non_victims.map { |n| final_sum += n.evidence_count }
    Logger.debug "Signals consumed: #{initial_sum - final_sum}"
  end
  
  def generate_signals_and_profiles(num_signals, non_victims, difficulty)
  ###
    # Generate a distribution. For now, just randomly add evidence to NPCs, and
    # when we're done, use the variance to tell how difficult it is. A variance
    # of 6 is pretty big (eg. distro is [6, 6, 12]; more than that is too much.
    # A variance of 2 or less means we have a close distribution, which is good
    # for very difficult games.
    num_signals.times do
      npc = non_victims.sample
      npc.evidence_count += 1      
    end
    
    # pick a variance from 6 (d=0) to 1.5 (d=10), uniformly distributed across difficulty
    target_variance = 6 - (difficulty * 4.5 / 10)    
    epsilon = 1
    v = non_victims.collect { |n| n.evidence_count }.variance
    Logger.debug "Target variance is #{target_variance}; starting with #{v}..."
    Logger.debug "\tEarliest distro is #{non_victims}"
    
    # Not within epsilon? we need to tweak variance.
    while (v - target_variance).abs >= epsilon
      if v > target_variance
        # Decrease variance. Decrease the max by one and increase the min by one.
        max = max_evidence_npc(non_victims)
        min = min_evidence_npc(non_victims)
        Logger.debug "\tVariance too high; swapping #{max} with #{min}"
        max.evidence_count -= 1
        min.evidence_count += 1        
      else
        # Increase variance. Take two random people and swap. It works. Somehow.
        r1 = non_victims.sample
        r2 = (non_victims - [r1]).sample
        Logger.debug "\tVariance too low; swapping #{r1} with #{r2}"
        r1.evidence_count -= 1
        r2.evidence_count += 1
      end
      
      v = non_victims.collect { |n| n.evidence_count }.variance
      Logger.debug "New v=#{v}"
    end
    
    #
    ### End distribution
    
    # For now, the killer has the most signals. Swap to ensure that.
    non_victims.each do |n|
      if n.evidence_count > @killer.evidence_count
        temp = @killer.evidence_count        
        @killer.evidence_count = n.evidence_count
        n.evidence_count = temp
      end
    end
    
    # Make sure nobody ties with us. Always be one more.
    # TODO: the killer shouldn't necessarily have more signals, but you should
    # be able to rule out people with more signals or better signals than him/her.
    @killer.evidence_count += 1
  end
  
  def max_evidence_npc(npcs)
    max_npc = npcs.first
    
    npcs.each do |n|
      if n.evidence_count > max_npc.evidence_count
        max_npc = n
      end
    end
    
    return max_npc
  end
  
  def min_evidence_npc(npcs)
    min_npc = npcs.first
    
    npcs.each do |n|
      if n.evidence_count < min_npc.evidence_count
        min_npc = n
      end
    end
    
    return min_npc
  end
  
  def generate_killers_alibi(non_killers)
    data = ExternalData::instance
    
    # % chance of having a strong alibi as the killer
    strong_alibi = rand(100) <= data.get(:strong_alibi_probability)
    Logger.debug " Killer's alibi is strong? #{strong_alibi}"
    Logger.debug "Non-killers: #{non_killers.collect {|n| n.name}}"
    
    if (strong_alibi)      
      # Make a pair, or a "ring" of three people who were together
      # 40% chance to be a ring
      make_ring = true if rand(100) <= data.get(:ring_alibi_probability)
      if make_ring
        n1 = non_killers.pop
        n2 = non_killers.pop        
        n1.alibi_person = n2
        n2.alibi_person = @killer
        @killer.alibi_person = n1
        Logger.debug "Killer uses a ring-type alibi: #{@killer.name}, #{n1.name}, #{n2.name}}"
      else
        alibi = non_killers.pop
        @killer.alibi_person = alibi
        alibi.alibi_person = @killer
        Logger.debug "Killer has a mutual alibi with #{alibi.name}"
      end
    elsif rand(100) <= data.get(:alone_alibi_probability)
      Logger.debug 'Killer claims to be alone as their alibi.'
      @killer.alibi_person = nil
    else
      @killer.evidence_count -= 1 # weak alibi: one indicator
      @killer.alibi_person = non_killers.sample
      Logger.debug "Killer has an obvious alibi which #{@killer.alibi_person.name} will not verify"
    end
  end
  
  def generate_alibis(non_killers)  
    # Pick two random people and link their alibis
    # To deal with odd numbers, make a trio
    while non_killers.size > 0 do
      if (non_killers.count == 1)
        loner = non_killers.pop
        loner.alibi_person = nil
        loner.evidence_count -= 1
      else
        n1 = non_killers.pop
        n2 = non_killers.pop
        
        if non_killers.size % 2 == 1
          if rand(100) <= ExternalData::instance.get(:alone_alibi_probability)
            n1.alibi_person = n2
            n2.alibi_person = n1
            Logger.debug "Alibi: #{n1.name} <=> #{n2.name}"
            n3 = non_killers.pop
            n3.alibi_person = nil
            n3.evidence_count -= 1
            Logger.debug "Alibi: #{n3.name} was alone"
          else
            # ring alibi
            n3 = non_killers.pop
            n1.alibi_person = n2
            n2.alibi_person = n3
            n3.alibi_person = n1
            Logger.debug "Alibi: Ring of [#{n1.name}, #{n2.name}, #{n3.name}]"
          end
        else
          Logger.debug "Alibi: #{n1.name} <=> #{n2.name}"
          n1.alibi_person = n2
          n2.alibi_person = n1
        end
      end
    end
  end
end