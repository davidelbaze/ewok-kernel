/* \file syscalls-cfg-mem.h
 *
 * Copyright 2018 The wookey project team <wookey@ssi.gouv.fr>
 *   - Ryad     Benadjila
 *   - Arnauld  Michelizza
 *   - Mathieu  Renard
 *   - Philippe Thierry
 *   - Philippe Trebuchet
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *     Unless required by applicable law or agreed to in writing, software
 *     distributed under the License is distributed on an "AS IS" BASIS,
 *     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *     See the License for the specific language governing permissions and
 *     limitations under the License.
 *
 */
#ifndef SYSCALL_CFG_MEM_H
#define SYSCALL_CFG_MEM_H

#include "syscalls.h"
#include "syscalls-utils.h"
#include "types.h"
#include "tasks.h"

void sys_cfg_dev_map(       task_t      *caller,
                     __user regval_t    *regs,
                            e_task_mode  mode);

void sys_cfg_dev_unmap(       task_t      *caller,
                       __user regval_t    *regs,
                              e_task_mode  mode);

#endif/*!SYSCALL_CFG_MEM_H*/
