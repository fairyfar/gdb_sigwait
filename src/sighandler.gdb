#################################
# Scripted by FairyFar. 
# http://www.200yi.com
#################################

### Global variables
init-if-undefined $_fgdb_g_script_inited = 0
init-if-undefined $_fgdb_g_main_bp_idx = 0
init-if-undefined $_fgdb_g_sigint_bp_idx = 0
init-if-undefined $_fgdb_g_hooked_sigint = 0
init-if-undefined $_fgdb_g_set_breakon_sigint = 0

### Initialize
define _fgdb_init
  if !$_fgdb_g_script_inited
    set confirm off
    py import re
    set variable $_fgdb_g_script_inited = 1
  end
end

### Find breakpoint via name
define _fgdb_find_info
  set variable $hk_found_info = 0
  py hk_info_bp = gdb.execute($arg0, to_string = True)
  py hk_found_info = "1" if re.search(r"[<| |\t]\b" + $arg1 + r"\b", hk_info_bp, 0) else "0"
  py gdb.execute('set variable $hk_found_info = ' + hk_found_info, to_string = True)
end

### Try to set a breakpoint on main
define _fgdb_set_breakon_main
  _fgdb_find_info "info breakpoints" "main"
  if !$hk_found_info
    #set breakpoint on main
    py hk_b_main = gdb.execute('break main', to_string = True)
    py hk_b_main_re = re.search("Breakpoint \d+", hk_b_main, 0)
    py gdb.execute('set variable $_fgdb_g_main_bp_idx = ' + (hk_b_main_re.group().split()[1] if hk_b_main_re else "0"), to_string = True)
  end
end

### Try to set a breakpoint on gdb_breakon_sigint
define _fgdb_breakon_sigint
  if !$_fgdb_g_hooked_sigint
    set variable $_fgdb_g_hooked_sigint = 1

    _fgdb_find_info "info functions gdb_breakon_sigint" "gdb_breakon_sigint"
    if $hk_found_info
      ignore-errors set variable g_enable_breakon_sigint = 1
      set variable $_fgdb_g_set_breakon_sigint = 1

      _fgdb_find_info "info breakpoints" "gdb_breakon_sigint"
      if !$hk_found_info
        py hk_b_sigint = gdb.execute('break gdb_breakon_sigint', to_string = True)
        py hk_b_sigint_re = re.search("Breakpoint \d+", hk_b_sigint, 0)
        py gdb.execute('set variable $_fgdb_g_sigint_bp_idx = ' + (hk_b_sigint_re.group().split()[1] if hk_b_sigint_re else "0"), to_string = True)
      end
      printf "Auto set a breakpoint on gdb_breakon_sigint.\n"
    end
  end
end

define _fgdb_unbreakon_sigint
  set variable $_fgdb_g_hooked_sigint = 0
  if $_fgdb_g_set_breakon_sigint
    ignore-errors set variable g_enable_breakon_sigint = 0
    set variable $_fgdb_g_set_breakon_sigint = 0

    # delete breakpoints
    if $_fgdb_g_sigint_bp_idx > 0
      delete breakpoints $_fgdb_g_sigint_bp_idx
      set variable $_fgdb_g_sigint_bp_idx = 0
    end
    if $_fgdb_g_main_bp_idx > 0
      delete breakpoints $_fgdb_g_main_bp_idx
      set variable $_fgdb_g_main_bp_idx = 0
    end
  end
end

define _fgdb_enable_breakpoint_sigint
  if $_fgdb_g_sigint_bp_idx > 0
    enable breakpoints $_fgdb_g_sigint_bp_idx
  end
end

define _fgdb_deleted_breakpoints
  if $_fgdb_g_sigint_bp_idx > 0
    _fgdb_find_info "info breakpoints" "gdb_breakon_sigint"
    if !$hk_found_info
      set variable $_fgdb_g_sigint_bp_idx = 0
      set variable $_fgdb_g_hooked_sigint = 0
      ignore-errors set variable g_enable_breakon_sigint = 0
    end
  end
  if $_fgdb_g_main_bp_idx > 0
    _fgdb_find_info "info breakpoints" "main"
    if !$hk_found_info
      set variable $_fgdb_g_main_bp_idx = 0
    end
  end
end

### hook run command
define hook-run
  _fgdb_set_breakon_main
end

### hook quit command
define hook-quit
  _fgdb_unbreakon_sigint
end

### hook stop command
define hook-stop
  _fgdb_breakon_sigint
end

### hook detach command
define hook-detach
  _fgdb_unbreakon_sigint
end

### hookpost disable command
define hookpost-disable
  _fgdb_enable_breakpoint_sigint
end

### hookpost disable breakpoints command
define disable hookpost-breakpoints
  _fgdb_enable_breakpoint_sigint
end

### hookpost delete command
define hookpost-delete
  _fgdb_deleted_breakpoints
end

### hookpost delete breakpoints command
define delete hookpost-breakpoints
  _fgdb_deleted_breakpoints
end

_fgdb_init

