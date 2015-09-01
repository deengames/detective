require 'scripts/name_generator'
require 'scripts/models/npc'

# A wrapper around the RPG Maker event. It exposes some properties and stuff, and methods like die.
class SuspectNpc < Npc
    
  attr_accessor :alibi_person, :map_id, :age, :profession
  
  NPC_PROFESSIONS = ['janitor', 'programmer', 'accountant', 'business analyst', 'personal trainer', 'CEO', 'teacher', 'cop', 'journalist']
  BLOOD_TYPES = ['A', 'B', 'AB', 'O']
  NEGLIBLE_CRIMES = ['petty theft', 'shoplifting', 'vandalism', 'breaking and entering']
  MINOR_CRIMES = ['extortion', 'assault', 'robbery', 'embezzlement', 'substance abuse']
  MAJOR_CRIMES = ['armed robbery', 'homicide', 'kidnapping', 'arson', 'child abuse']
  
  # move_speed = 1-6
  # move_frequency = 1-5
  # spritesheet_file is the filename used for the graphic, eg. Actor1.
  # spritesheet_index is the base 0 index (0-7; first row, then second row)
  # template_id is the ID of the event we're copying, on map with ID=DATA_MAP_ID
  def initialize(map_id, name, spritesheet_file = nil, spritesheet_index = nil, template_id = nil, npc_speed = nil, npc_frequency = nil)
    super(name, spritesheet_file, spritesheet_index, template_id, npc_speed, npc_frequency)
    @map_id = map_id
    
    # basic facts
    @age = 20 + rand(15)    
    @profession = NPC_PROFESSIONS.sample
    @blood_type = pick_blood_type
    @criminal_record = generate_criminal_record
  end
 
  def talk    
    if @dead
      message = "#{@name} is dead ..."
    else
      message = "#{@name}: I was with #{@alibi_person.name} all day."
    end
    Game_Interpreter.instance.show_message(message)
    DetectiveGame::instance.notebook.note(message)
  end
  
  def profile
    return "#{@name} is a #{@age} year-old #{@profession} with blood type #{@blood_type}.\n#{@criminal_record}"
  end
  
  private
  
  def pick_blood_type
    # Based on culmulative distribution from http://www.redcrossblood.org/learn-about-blood/blood-types
    # O: 48% A: 31% B: 16% AB: 4%
    # i.e. 50% O, 80% O and A
    blood_picked = rand(100)
    return 'O' if blood_picked < 48
    return 'A' if blood_picked < 48 + 31
    return 'B' if blood_picked < 48 + 31 + 16
    return 'AB'
  end
  
  def generate_criminal_record
    severity = rand(100)
    # 30% nothing, 30% mild, 25% medium, 15% severe
    return "#{@name} has no prior criminal record" if severity < 30
    return "#{@name}'s criminal record contains a few counts of #{NEGLIBLE_CRIMES.sample}" if severity < 60
    return "#{@name} served a short jail sentence for #{MINOR_CRIMES.sample}" if severity < 85
    return "#{@name} served several years of combined jail time for #{MAJOR_CRIMES.sample(2).join(' and ')}" # >= 85
  end
end