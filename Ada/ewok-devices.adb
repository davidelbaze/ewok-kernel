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

with ewok.perm;                  use ewok.perm;
with ewok.exported.devices;      use ewok.exported.devices;
with ewok.exported.interrupts;   use ewok.exported.interrupts;
with ewok.exported.gpios;        use ewok.exported.gpios;
with ewok.interrupts;            use ewok.interrupts;
with ewok.sanitize;
with ewok.gpio;
with ewok.mpu;
with ewok.exti;
with ewok.tasks; use ewok.tasks;
with soc.nvic;
with soc.gpio;
with soc.interrupts;             use soc.interrupts;
with c.socinfo; use type c.socinfo.t_device_soc_infos_access;
with types.c;
with debug;

package body ewok.devices
   with spark_mode => off
is

   procedure init
   is begin
      for i in registered_device'range loop
         registered_device(i).status    := DEV_STATE_UNUSED;
         registered_device(i).task_id   := ID_UNUSED;
         registered_device(i).devinfo   := NULL;
         -- FIXME initialize registered_device(i).udev with 0 values
      end loop;
   end init;


   function get_task_from_id(dev_id : t_device_id)
      return t_task_id
   is
   begin
      return registered_device(dev_id).task_id;
   end get_task_from_id;


   function get_user_device (dev_id : t_device_id)
      return ewok.exported.devices.t_user_device_access
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return registered_device(dev_id).udev'access;
   end get_user_device;


   function get_user_device_size (dev_id : t_device_id)
      return unsigned_16
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return registered_device(dev_id).udev.size;
   end get_user_device_size;


   function get_user_device_addr (dev_id : t_device_id)
      return system_address
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return registered_device(dev_id).udev.base_addr;
   end get_user_device_addr;


   function is_user_device_region_ro (dev_id : t_device_id)
      return boolean
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return boolean (registered_device(dev_id).devinfo.all.ro);
   end is_user_device_region_ro;


   function get_user_device_subregions_mask (dev_id : t_device_id)
      return unsigned_8
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return registered_device(dev_id).devinfo.all.subregions;
   end get_user_device_subregions_mask;


   function get_interrupt_config_from_interrupt
     (interrupt : soc.interrupts.t_interrupt)
      return ewok.exported.interrupts.t_interrupt_config_access
   is
      dev_id : t_device_id;
   begin

      -- Retrieving the dev_id from the interrupt
      dev_id := ewok.interrupts.get_device_from_interrupt (interrupt);
      if dev_id = ID_DEV_UNUSED then
         return NULL;
      end if;

      -- Looking at each interrupts configured for this device
      -- to retrieve the proper interrupt configuration informations
      for i in 1 .. registered_device(dev_id).udev.interrupt_num loop
         if registered_device(dev_id).udev.interrupts(i).interrupt = interrupt
         then
            return registered_device(dev_id).udev.interrupts(i)'access;
         end if;
      end loop;
      return NULL;
   end get_interrupt_config_from_interrupt;

   ------------------------
   -- Device registering --
   ------------------------

   procedure get_registered_device_entry
     (dev_id   : out t_device_id;
      success  : out boolean)
   is
   begin
      for id in registered_device'range loop
         if registered_device(id).status = DEV_STATE_UNUSED then
            registered_device(id).status := DEV_STATE_RESERVED;
            dev_id  := id;
            success := true;
            return;
         end if;
      end loop;
      dev_id  := ID_DEV_UNUSED;
      success := false;
   end get_registered_device_entry;


   procedure release_registered_device_entry (dev_id : t_device_id)
   is begin
      registered_device(dev_id).status    := DEV_STATE_UNUSED;
      registered_device(dev_id).task_id   := ID_UNUSED;
      registered_device(dev_id).devinfo   := NULL;
      -- FIXME initialize registered_device(dev_id).udev with 0 values
   end release_registered_device_entry;


   procedure register_device
     (task_id  : in  t_task_id;
      udev     : in  ewok.exported.devices.t_user_device_access;
      dev_id   : out t_device_id;
      success  : out boolean)
   is
      devinfo  : c.socinfo.t_device_soc_infos_access;
      len      : constant natural := types.c.len (udev.all.name);
      name     : string (1 .. len);
   begin

      -- Convert C name to Ada string type for further log messages
      types.c.to_ada (name, udev.all.name);

      -- Is it an existing device ?
      -- Note: GPIOs (size = 0) are not considered as devices despite a task
      --       can register them. Thus, we don't look for them in c.socinfo
      --       table.
      if udev.all.size /= 0 then
         devinfo := c.socinfo.soc_devmap_find_device
           (udev.all.base_addr, udev.all.size);
         if devinfo = NULL then
            debug.log (debug.WARNING, "Can't find device " & name & "(addr:" &
               system_address'image (udev.all.base_addr) & ", size:" &
               unsigned_16'image (udev.all.size) & ")");
            success := false;
            return;
         end if;
      end if;

      -- Is it already used ?
      -- Note: GPIOs alone are not considered as devices. When the user
      --       declares lone GPIOs, devinfo is NULL
      for id in registered_device'range loop
         if registered_device(id).status  /= DEV_STATE_UNUSED and then
            registered_device(id).devinfo /= NULL and then
            registered_device(id).devinfo = devinfo
         then
            debug.log (debug.WARNING, "Device " & name & " is already used");
            success := false;
            return;
         end if;
      end loop;

      -- Are the GPIOs already used ?
      for i in 1 .. udev.gpio_num loop
         if ewok.gpio.is_used (udev.gpios(i).kref) then
            debug.log (debug.WARNING,
               "Device " & name & ": some GPIOs are already used");
            success := false;
            return;
         end if;
      end loop;

      -- Are the related EXTIs already used ?
      for i in 1 .. udev.gpio_num loop
         if boolean (udev.gpios(i).settings.set_exti) and then
            ewok.exti.is_used (udev.gpios(i).kref)
         then
            debug.log (debug.WARNING,
               "Device " & name & ": some EXTIs are already used");
            success := false;
            return;
         end if;
      end loop;

      -- Is it possible to register interrupt handlers ?
      for i in 1 .. udev.interrupt_num loop
         if ewok.interrupts.is_interrupt_already_used
              (udev.interrupts(i).interrupt)
         then
            debug.log (debug.WARNING,
               "Device " & name & ": some interrupts are already used");
            success := false;
            return;
         end if;
      end loop;

      -- Is it possible to register a device ?
      get_registered_device_entry (dev_id, success);

      if not success then
         debug.log (debug.WARNING,
            "register_device(): no slot left to register the device");
         return;
      end if;

      -- Registering the device 
      debug.log (debug.INFO, "Registered device " & name & " (0x" &
         system_address'image (udev.all.base_addr) & ")");

      registered_device(dev_id).udev      := udev.all;
      registered_device(dev_id).task_id   := task_id;
      registered_device(dev_id).is_mapped := false;
      registered_device(dev_id).devinfo   := devinfo;
      registered_device(dev_id).status    := DEV_STATE_REGISTERED;

      -- Registering GPIOs
      for i in 1 .. udev.gpio_num loop
         ewok.gpio.register (task_id, dev_id, udev.gpios(i)'access, success);
         if not success then
            raise program_error;
         end if;
         debug.log (debug.INFO,
            "Registered GPIO port" &
            soc.gpio.t_gpio_port_index'image (udev.gpios(i).kref.port) &
            " pin " &
            soc.gpio.t_gpio_pin_index'image (udev.gpios(i).kref.pin));
      end loop;

      -- Registering EXTIs
      for i in 1 .. udev.gpio_num loop
         ewok.exti.register (udev.gpios(i)'access, success);
         if not success then
            raise program_error;
         end if;
      end loop;

      -- Registering handlers
      for i in 1 .. udev.interrupt_num loop
         ewok.interrupts.set_interrupt_handler
           (udev.interrupts(i).interrupt,
            udev.interrupts(i).handler,
            task_id,
            dev_id,
            success);
         if not success then
            raise program_error;
         end if;
      end loop;

      success := true;

   end register_device;


   procedure enable_device
     (dev_id   : in  t_device_id;
      success  : out boolean)
   is
      irq         : soc.nvic.t_irq_index;
      interrupt   : t_interrupt;
   begin

      -- Check if the device was already configured
      if registered_device(dev_id).status /= DEV_STATE_REGISTERED then
         raise program_error;
      end if;

      -- Configure and enable GPIOs
      for i in 1 .. registered_device(dev_id).udev.gpio_num loop
         ewok.gpio.config (registered_device(dev_id).udev.gpios(i)'access);
         if registered_device(dev_id).udev.gpios(i).exti_trigger /=
               GPIO_EXTI_TRIGGER_NONE
         then
            ewok.exti.enable (registered_device(dev_id).udev.gpios(i).kref);
         end if;
      end loop;

      -- For each interrupt, enable its associated IRQ in the NVIC
      for i in 1 .. registered_device(dev_id).udev.interrupt_num loop
         interrupt := registered_device(dev_id).udev.interrupts(i).interrupt;
         irq       := soc.nvic.to_irq_number (interrupt);
         soc.nvic.enable_irq (irq);
         debug.log (debug.INFO, "IRQ enabled" & soc.nvic.t_irq_index'image (irq) & " (int:"
            & t_interrupt'image (interrupt) & ")");
      end loop;

      -- Enable device's clock
      if registered_device(dev_id).devinfo /= NULL then
         c.socinfo.soc_devmap_enable_clock (registered_device(dev_id).devinfo.all);
         declare
            udev : constant t_user_device := registered_device(dev_id).udev;
            name : string (1 .. types.c.len (udev.name));
         begin
            types.c.to_ada (name, udev.name);
            debug.log (debug.INFO, "Enabled device " & name);
         end;
      end if;

      registered_device(dev_id).status := DEV_STATE_ENABLED;
      if registered_device(dev_id).udev.map_mode = DEV_MAP_AUTO then
         registered_device(dev_id).is_mapped := true;
      end if;
      success := true;
   end enable_device;


   function sanitize_user_defined_interrupt
     (udev     : in  ewok.exported.devices.t_user_device_access;
      config   : in  ewok.exported.interrupts.t_interrupt_config;
      task_id  : in  t_task_id)
      return boolean
   is
   begin

      if not ewok.sanitize.is_word_in_txt_slot
            (to_system_address (config.handler), task_id)
      then
         debug.log (debug.WARNING, "Device handler not in TXT slot");
         return false;
      end if;

      if config.interrupt not in INT_WWDG .. INT_HASH_RNG
      then
         debug.log (debug.WARNING, "Device interrupt not in range");
         return false;
      end if;

      if config.mode = ISR_FORCE_MAINTHREAD and then
         not ewok.perm.ressource_is_granted (PERM_RES_TSK_FISR, task_id)
      then
         debug.log (debug.WARNING, "Device ISR_FORCE_MAINTHREAD not allowed");
         return false;
      end if;

      --
      -- Verify posthooks
      --

      for i in 1 .. MAX_POSTHOOK_INSTR loop

         if not config.posthook.action(i).instr'valid then
            debug.log (debug.WARNING,
               "Device posthook: invalid action requested");
            return false;
         end if;

         case config.posthook.action(i).instr is
            when POSTHOOK_NIL       => null;

            when POSTHOOK_READ      =>
               if config.posthook.action(i).read.offset > udev.all.size - 4 or
                  (config.posthook.action(i).read.offset and 2#11#) > 0
               then
                  debug.log (debug.WARNING,
                     "Device posthook: wrong READ offset");
                  return false;
               end if;

            when POSTHOOK_WRITE     =>
               if config.posthook.action(i).write.offset > udev.all.size - 4 or
                  (config.posthook.action(i).write.offset and 2#11#) > 0
               then
                  debug.log (debug.WARNING,
                     "Device posthook: wrong WRITE offset");
                  return false;
               end if;

            when POSTHOOK_WRITE_REG =>
               if config.posthook.action(i).write_reg.offset_dest >
                     udev.all.size - 4
                  or (config.posthook.action(i).write_reg.offset_dest and 2#11#)
                        > 0
                  or config.posthook.action(i).write_reg.offset_src >
                        udev.all.size - 4
                  or (config.posthook.action(i).write_reg.offset_src and 2#11#)
                        > 0
               then
                  debug.log (debug.WARNING,
                     "Device posthook: wrong AND offset");
                  return false;
               end if;

            when POSTHOOK_WRITE_MASK =>

               if config.posthook.action(i).write_mask.offset_dest >
                     udev.all.size - 4
                  or (config.posthook.action(i).write_mask.offset_dest and 2#11#)
                        > 0
                  or config.posthook.action(i).write_mask.offset_src >
                        udev.all.size - 4
                  or (config.posthook.action(i).write_mask.offset_src and 2#11#)
                        > 0
                  or config.posthook.action(i).write_mask.offset_mask >
                        udev.all.size - 4
                  or (config.posthook.action(i).write_mask.offset_mask and 2#11#)
                        > 0
               then
                  debug.log (debug.WARNING,
                     "Device posthook: wrong MASK offset");
                  return false;
               end if;
         end case;

      end loop;

      return true;

   end sanitize_user_defined_interrupt;


   function sanitize_user_defined_gpio
     (udev     : in  ewok.exported.devices.t_user_device_access;
      config   : in  ewok.exported.gpios.t_gpio_config;
      task_id  : in  t_task_id)
      return boolean
   is
      pragma unreferenced (udev);
   begin

      if config.exti_trigger /= GPIO_EXTI_TRIGGER_NONE and then
         not ewok.perm.ressource_is_granted (PERM_RES_DEV_EXTI, task_id)
      then
         debug.log (debug.WARNING, "Device PERM_RES_DEV_EXTI not allowed");
         return false;
      end if;

      if config.exti_handler /= 0 and then
         not ewok.sanitize.is_word_in_txt_slot (config.exti_handler, task_id)
      then
         debug.log (debug.WARNING, "Device EXTI handler not in TXT slot");
         return false;
      end if;

      return true;

   end sanitize_user_defined_gpio;


   function sanitize_user_defined_device
     (udev     : in  ewok.exported.devices.t_user_device_access;
      task_id  : in  t_task_id)
      return boolean
   is
      devinfo : c.socinfo.t_device_soc_infos_access;
      ok       : boolean;

      len   : constant natural := types.c.len (udev.all.name);
      name  : string (1 .. natural'min (t_device_name'length, len));
   begin

      if udev.all.name(t_device_name'last) /= ASCII.NUL then
         types.c.to_ada (name, udev.all.name(1 .. t_device_name'length));
         debug.log (debug.WARNING, "Out-of-bound device name: " & name);
         return false;
      else
         types.c.to_ada (name, udev.all.name);
      end if;

      if udev.all.size /= 0 then
         devinfo :=
            c.socinfo.soc_devmap_find_device (udev.all.base_addr, udev.all.size);

         if devinfo = NULL then
            debug.log (debug.WARNING, "Device at addr" & system_address'image
               (udev.all.base_addr) & " with size" & unsigned_16'image (udev.all.size) &
               ": not found");
            return false;
         end if;

         if not ewok.perm.ressource_is_granted (devinfo.minperm, task_id) then
            debug.log (debug.WARNING, "Task" & t_task_id'image (task_id) &
               " has not access to device " & name);
            return false;
         end if;
      end if;

      for i in 1 .. udev.all.interrupt_num loop
         ok := sanitize_user_defined_interrupt
                 (udev, udev.all.interrupts(i), task_id);
         if not ok then
            debug.log (debug.WARNING, "Device " & name & ": invalid udev.interrupts parameter");
            return false;
         end if;
      end loop;

      for i in 1 .. udev.all.gpio_num loop
         ok := sanitize_user_defined_gpio (udev, udev.all.gpios(i), task_id);
         if not ok then
            debug.log (debug.WARNING, "Device " & name & ": invalid udev.gpios parameter");
            return false;
         end if;
      end loop;

      if udev.all.map_mode = DEV_MAP_VOLUNTARY then
         if not ewok.perm.ressource_is_granted (PERM_RES_MEM_DYNAMIC_MAP, task_id) then
            debug.log (debug.WARNING, "Task" & t_task_id'image (task_id) &
               " voluntary mapped device " & name & " not permited");
            return false;
        end if;
      end if;

      return true;

   end sanitize_user_defined_device;


   -------------------------------------------------
   -- Marking devices to be mapped in user memory --
   -------------------------------------------------

   procedure map_device
     (dev_id   : in  t_device_id;
      success  : out boolean)
   is
      task_id  : constant t_task_id := ewok.devices.get_task_from_id (dev_id);
      task_a   : constant t_task_access := ewok.tasks.get_task (task_id);
   begin

      -- The device is already mapped
      if registered_device(dev_id).is_mapped then
         success := true;
         return;
      end if;

      -- We are physically limited by the number of regions
      if task_a.all.num_devs_mmapped = ewok.mpu.MPU_MAX_EMPTY_REGIONS then
         success := false;
         return;
      end if;

      registered_device(dev_id).is_mapped := true;
      task_a.all.num_devs_mmapped := task_a.all.num_devs_mmapped + 1;
      success := true;
   end map_device;


   procedure unmap_device
     (dev_id   : in  t_device_id;
      success  : out boolean)
   is
      task_id  : constant t_task_id := ewok.devices.get_task_from_id (dev_id);
      task_a   : constant t_task_access := ewok.tasks.get_task (task_id);
   begin
      -- The device is already unmapped
      if not registered_device(dev_id).is_mapped then
         success := true;
         return;
      end if;

      task_a.all.num_devs_mmapped := task_a.all.num_devs_mmapped - 1;
      registered_device(dev_id).is_mapped := false;
      success := true;
   end unmap_device;


   function is_mapped (dev_id : t_device_id)
      return boolean
   is
   begin
      if dev_id = ID_DEV_UNUSED then
         raise program_error;
      end if;
      return registered_device(dev_id).is_mapped;
   end is_mapped;


end ewok.devices;
