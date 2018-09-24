--
-- Copyright 2018 The wookey project team <wookey@ssi.gouv.fr>
--   - Ryad     Benadjila
--   - Arnauld  Michelizza
--   - Mathieu  Renard
--   - Philippe Thierry
--   - Philippe Trebuchet
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
--     Unless required by applicable law or agreed to in writing, software
--     distributed under the License is distributed on an "AS IS" BASIS,
--     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--     See the License for the specific language governing permissions and
--     limitations under the License.
--
--

with system.machine_code;

with m4.scb;
with m4.systick;
with debug;
with soc.interrupts;       use soc.interrupts;
with ewok.tasks;           use ewok.tasks;
with ewok.sched;
with ewok.tasks_shared;    use ewok.tasks_shared;
with ewok.devices_shared;  use type ewok.devices_shared.t_device_id;
with ewok.isr;

package body ewok.interrupts.handler
   with spark_mode => off
is

   function hardfault_handler
     (frame_a : ewok.t_stack_frame_access) return ewok.t_stack_frame_access
   is
      cfsr : constant m4.scb.t_SCB_CFSR := m4.scb.SCB.CFSR;
   begin

      if cfsr.MMFSR.IACCVIOL  then debug.log (debug.WARNING, "+cfsr.MMFSR.IACCVIOL"); end if;
      if cfsr.MMFSR.DACCVIOL  then debug.log (debug.WARNING, "+cfsr.MMFSR.DACCVIOL"); end if;
      if cfsr.MMFSR.MUNSTKERR then debug.log (debug.WARNING, "+cfsr.MMFSR.MUNSTKERR"); end if;
      if cfsr.MMFSR.MSTKERR   then debug.log (debug.WARNING, "+cfsr.MMFSR.MSTKERR"); end if;
      if cfsr.MMFSR.MLSPERR   then debug.log (debug.WARNING, "+cfsr.MMFSR.MLSPERR"); end if;
      if cfsr.MMFSR.MMARVALID then debug.log (debug.WARNING, "+cfsr.MMFSR.MMARVALID"); end if;

      if cfsr.BFSR.IBUSERR    then debug.log (debug.WARNING, "+cfsr.BFSR.IBUSERR"); end if;
      if cfsr.BFSR.PRECISERR  then debug.log (debug.WARNING, "+cfsr.BFSR.PRECISERR"); end if;
      if cfsr.BFSR.IMPRECISERR then debug.log (debug.WARNING, "+cfsr.BFSR.IMPRECISERR"); end if;
      if cfsr.BFSR.UNSTKERR   then debug.log (debug.WARNING, "+cfsr.BFSR.UNSTKERR"); end if;
      if cfsr.BFSR.STKERR     then debug.log (debug.WARNING, "+cfsr.BFSR.STKERR"); end if;
      if cfsr.BFSR.LSPERR     then debug.log (debug.WARNING, "+cfsr.BFSR.LSPERR"); end if;
      if cfsr.BFSR.BFARVALID  then debug.log (debug.WARNING, "+cfsr.BFSR.BFARVALID"); end if;

      if cfsr.UFSR.UNDEFINSTR then debug.log (debug.WARNING, "+cfsr.UFSR.UNDEFINSTR"); end if;
      if cfsr.UFSR.INVSTATE   then debug.log (debug.WARNING, "+cfsr.UFSR.INVSTATE"); end if;
      if cfsr.UFSR.INVPC      then debug.log (debug.WARNING, "+cfsr.UFSR.INVPC"); end if;
      if cfsr.UFSR.NOCP       then debug.log (debug.WARNING, "+cfsr.UFSR.NOCP"); end if;
      if cfsr.UFSR.UNALIGNED  then debug.log (debug.WARNING, "+cfsr.UFSR.UNALIGNED"); end if;
      if cfsr.UFSR.DIVBYZERO  then debug.log (debug.WARNING, "+cfsr.UFSR.DIVBYZERO"); end if;

      debug.log (debug.WARNING,
         "registers (frame at " &
         system_address'image (to_system_address (frame_a)) &
         ", EXC_RETURN " & unsigned_32'image (frame_a.all.LR) & ")");

      debug.log (debug.WARNING,
         "R0 " & unsigned_32'image (frame_a.all.R0) &
         ", R1 " & unsigned_32'image (frame_a.all.R1) &
         ", R2 " & unsigned_32'image (frame_a.all.R2) &
         ", R3 " & unsigned_32'image (frame_a.all.R3));

      debug.log (debug.WARNING,
         "R4 " & unsigned_32'image (frame_a.all.R4) &
         ", R5 " & unsigned_32'image (frame_a.all.R5) &
         ", R6 " & unsigned_32'image (frame_a.all.R6) &
         ", R7 " & unsigned_32'image (frame_a.all.R7));

      debug.log (debug.WARNING,
         "R8 " & unsigned_32'image (frame_a.all.R8) &
         ", R9 " & unsigned_32'image (frame_a.all.R9) &
         ", R10 " & unsigned_32'image (frame_a.all.R10) &
         ", R11 " & unsigned_32'image (frame_a.all.R11));

      debug.log (debug.WARNING,
         "R12 " & unsigned_32'image (frame_a.all.R12) &
         ", PC " & unsigned_32'image (frame_a.all.PC) &
         ", LR " & unsigned_32'image (frame_a.all.LR));

      debug.panic("panic!");

      return frame_a;

   end hardfault_handler;


   function systick_default_handler
     (frame_a : ewok.t_stack_frame_access)
      return ewok.t_stack_frame_access
   is
   begin
      m4.systick.increment;
      return frame_a;
   end systick_default_handler;


   function default_sub_handler
     (frame_a : t_stack_frame_access)
      return t_stack_frame_access
   is
      it          : t_interrupt;
      current_id  : ewok.tasks_shared.t_task_id;
      new_frame_a : t_stack_frame_access;
      ttype       : t_task_type;
   begin

      it := soc.interrupts.get_interrupt;
      interrupt_table(it).count := interrupt_table(it).count + 1;

      -- FIXME - Differenciation between sync / async ISR is not clear.
      --         Maybe using a specific flag:
      --            "if interrupt_table(it).async then (...)"

      -- External interrupt
      if it >= INT_WWDG then
         if interrupt_table(it).task_id /= ewok.tasks_shared.ID_UNUSED
         then
            -- User or kernel ISR: asynchronous execution (postponed)
            ewok.isr.postpone_isr
              (it,
               interrupt_table(it).handler,
               interrupt_table(it).task_id,
               frame_a);
         elsif interrupt_table(it).handler /= NULL
         then
            -- Execute kernel ISR w/o associated device (handler is not
            -- postponed)
            interrupt_table(it).handler (frame_a);
         else
            debug.panic ("Unhandled interrupt " & t_interrupt'image (it));
         end if;
         new_frame_a := frame_a;

      -- System exceptions are synchronously executed (handler is not postponed)
      else

         if interrupt_table(it).htype = DEFAULT_HANDLER then
            interrupt_table(it).handler (frame_a);
            new_frame_a := frame_a;
         else
            new_frame_a := interrupt_table(it).task_switch_handler (frame_a);
         end if;
      end if;

      -- Task's execution mode must be transmitted to the Default_Handler
      -- to run it with the proper privilege (set in the CONTROL register).
      -- The current function uses R0 and R1 registers to return the
      -- following values:
      --    R0 - address of the task frame
      --    R1 - execution mode

      current_id := ewok.sched.get_current;
      if current_id /= ID_UNUSED then
         ttype := ewok.tasks.tasks_list(current_id).ttype;
      else
         ttype := TASK_TYPE_KERNEL;
      end if;

      system.machine_code.asm
        ("mov r1, %0",
         inputs   => t_task_type'asm_input ("r", ttype),
         clobber  => "r1",
         volatile => true);

      return new_frame_a;

   end default_sub_handler;


end ewok.interrupts.handler;
