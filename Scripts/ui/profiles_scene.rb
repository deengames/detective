# Hierarchy of OK/OK/OK: suspects => details => status
class Scene_Profiles < Scene_ItemBase
  # Start Processing
  def start
    super
    create_suspects_window
    create_status_window
    create_details_window
    
    # trigger the UI for the first suspect to be correct
    @suspect_list.index = 0
    
  end

  def create_suspects_window
    @suspect_list = Window_SuspectsList.new
    @suspect_list.viewport = @viewport
    @suspect_list.set_handler(:ok,     method(:on_suspect_ok))
    @suspect_list.set_handler(:cancel, method(:return_scene))
  end

  def create_details_window
    wy = @suspect_list.y + @suspect_list.height
    wh = Graphics.height - wy  - @status_window.height
    @details_window = Window_SuspectDetails.new(0, wy, Graphics.width, wh)
    @details_window.viewport = @viewport
    @suspect_list.details_window = @details_window
    @details_window.set_handler(:ok, method(:on_details_ok))
    @details_window.set_handler(:cancel, method(:on_details_cancel))    
  end
  
  def create_status_window    
    @status_window = Window_SuspectsStatus.new
    @status_window.viewport = @viewport
    @suspect_list.status_window = @status_window
    @status_window.set_handler(:ok, method(:on_status_ok))
    @status_window.set_handler(:cancel, method(:on_status_cancel))
    @status_window.deactivate
  end

  # go to details list
  def on_suspect_ok    
    @suspect_list.deactivate
    @details_window.activate
    @details_window.select(0)
  end
  
  def on_status_cancel
    # go back to details list
    @status_window.deactivate
    @details_window.activate
    @details_window.select(0)
  end
  
  def on_status_ok    
    npc_index = @suspect_list.index
    status = @status_window.current_symbol
    DetectiveGame::instance.notebook.set_npc_status(npc_index, status)    
    on_status_cancel # go back to details list
  end
  
  def on_details_ok
    @status_window.activate
    @details_window.deactivate
    @details_window.unselect
  end
  
  def on_details_cancel
    @suspect_list.activate
    @details_window.deactivate
    @details_window.unselect
  end
end


class Window_SuspectsList < Window_HorzCommand
  attr_reader   :suspect_list, :status_window

  def initialize
    super(0, 0)
  end

  def window_width
    Graphics.width
  end
  
  ### Maximum number of items to show at one time. Items are fixed width :(
  def col_max
    return DetectiveGame::instance.npcs.count
  end

  def make_command_list
    DetectiveGame::instance.npcs.each do |n|
      add_command(n.name, n.name.to_sym)
    end
  end

  def details_window=(details_window)
    @details_window = details_window
    update
  end
  
  def status_window=(status_window)
    @status_window = status_window
    update
  end
  
  # Run when the selected index changes
  def index=(index)
    super
    return if @status_window.nil?
    data = DetectiveGame::instance.notebook.status_for(index)
    @status_window.select(data)
    
    @details_window.refresh # clears the old text    
    notes = DetectiveGame::instance.notebook.notes_for(:npc_index => index)
    profile = DetectiveGame::instance.npcs[index].profile
    text = "#{notes}#{profile}"
    @details_window.draw_text_ex(0, 0, text)
  end
end

class Window_SuspectsStatus < Window_HorzCommand
  MY_HEIGHT = 48 # reverse-engineered through experimentation
  attr_reader   :suspect_list, :status_window

  def initialize
    super(0, Graphics.height - MY_HEIGHT)
  end

  def window_width
    Graphics.width
  end
  
  ### Maximum number of items to show at one time. Items are fixed width :(
  def col_max
    return 3
  end

  def make_command_list
    # These must match the order in notebook.rb's status_for
    Notebook.STATUS_MAP.keys.each do |c|
      add_command(c.to_s.capitalize, c)
    end
  end
end

class Window_SuspectDetails < Window_Selectable
  def item_max
    return 99 # word-wrapping makes it impossible to actually count the right value.
  end
end