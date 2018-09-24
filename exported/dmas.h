/* \file dmas.h
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
#ifndef EXPORTED_DMAS_H_
#define EXPORTED_DMAS_H_

#include "../tasks-shared.h"

typedef enum {
  /** Reconfigure handlers (in or out, depending on direction) */
	DMA_RECONF_HANDLERS = 0b0000001,
  /** Reconfigure source buffer */
	DMA_RECONF_BUFIN 	= 0b0000010,
  /** Reconfigure destination buffer */
	DMA_RECONF_BUFOUT 	= 0b0000100,
  /** Reconfigure buffer size (in bytes) */
	DMA_RECONF_BUFSIZE 	= 0b0001000,
  /** Reconfigure DMA mode */
	DMA_RECONF_MODE 	= 0b0010000,
  /** Reconfigure DMA priority */
	DMA_RECONF_PRIO 	= 0b0100000,
  /** Reconfigure DMA direction */
	DMA_RECONF_DIR  	= 0b1000000,
  /** Reconfigure all fields (handlers, buffers, size, mode and priority */
	DMA_RECONF_ALL 		= 0b1111111,
} dma_reconf_mask_t;

typedef enum {
  /** Direct mode: copy source address content */
	DMA_DIRECT_MODE   = 0,
  /** FIFO mode: using FIFO indirection of address pointers */
	DMA_FIFO_MODE     = 1,
  /** Circular mode: using a circular buffer */
	DMA_CIRCULAR_MODE = 2
} dma_mode_t;

typedef enum {
  /** From device memory to main memory (flash, (S)RAM) */
	PERIPHERAL_TO_MEMORY = 0,
  /** From main memory (flash, (S)RAM) to device memory */
	MEMORY_TO_PERIPHERAL,
  /** From main memory to main memory */
	MEMORY_TO_MEMORY
} dma_dir_t;

/**
** \brief DMA Stream priority
**
** A best practice is to define a higher priority for device to memory than
** for memory to device stream when targetting the same device, avoiding
** device contention
*/
typedef enum {
	DMA_PRI_LOW,      /**< Low piority, lower one */
	DMA_PRI_MEDIUM,   /**< Medium priority */
	DMA_PRI_HIGH,     /**< High priority */
	DMA_PRI_VERY_HIGH /**< Very high priority */
} dma_prio_t;

/**
** \brief DMA Data unit size
*/
typedef enum {
	DMA_DS_BYTE,     /**< Data unit is one byte sized */
	DMA_DS_HALFWORD, /**< Data unit is Half-Word sized */
	DMA_DS_WORD      /**< Data unit is Word sized */
} dma_datasize_t;

typedef enum {
		    /** No burst */
	DMA_BURST_SINGLE,
		    /** 4 bytes burst reading */
	DMA_BURST_INC4,
		    /** 8 bytes burst reading */
	DMA_BURST_INCR8,
		    /** 16 bytes burst reading */
	DMA_BURST_INCR16
} dma_burst_t;

typedef enum {
    /** Flow control is made by DMA controller */
    DMA_FLOWCTRL_DMA = 0,
    /** Flow control is made by target peripheral */
    DMA_FLOWCTRL_DEV = 1,
} dma_flowctrl_t;

typedef void (*user_dma_handler_t) (uint8_t irq, uint32_t status);

/**
** \brief This is the global user DMA controler structure definition.
**
** This structure is passed to the kernel in order to declare a DMA channel.
** The DMA is configured by the kernel after parameters check (task slotting, etc.)
** The task ISR handlers will be able to reload the DMA controler but will not be
** authorized to reconfigure the in/out address or size of the DMA controler. Such
** operation requires the usage of a specific syscall.
**
** The DMA channel must correspond to an existing device that has already been declared
** by the task. Otherwhise, the DMA declaration returns SYS_E_DENIED.
**
** All the structure's fields are compared with the current SoC's DMA mapping to
** validate that the corresponding stream is able to respond to the request
*/
typedef struct {
	physaddr_t in_addr;	    /**< DMA input base address, for memory to memory or to peripheral only */
	physaddr_t out_addr;	    /**< DMA output base address for peripheral to memory or memory to memory only */
	dma_prio_t in_prio;	    /**< DMA priority for memory to peripheral */
	dma_prio_t out_prio;	    /**< DMA priority for peripheral to peripheral */
	uint16_t size;		    /**< DMA output size to copy (in bytes, whatever the datasize is) */
	uint8_t dma;		    /**< DMA controler identifier, (starting with 1 for DMA1, 2 for DMA2, etc.) */
	uint8_t channel;	    /**< DMA channel to configure */
	uint8_t stream;		    /**< DMA stream to configure */
    dma_flowctrl_t flow_control; /**< DMA Flow controller */
	dma_dir_t dir;		    /**< Current DMA direction */
	dma_mode_t mode;	    /**< Current DMA mode */
	bool mem_inc;		    /**< DMA increment for memory, when set to 0, the device doesn't increment
                                         the memory address at each read */
	bool dev_inc;		    /**< DMA increment for device, with the same behavior as the mem_inc, but
                                         for the device. Typically set to 0 when the DMA read (or write) to (from)
                                         a register */
	dma_datasize_t datasize;    /**< data unit size (byte, HW or Word, varies depending on the device specifications */
	dma_burst_t mem_burst;	    /**< type of DMA burst mode */
	dma_burst_t dev_burst;	    /**< type of DMA burst mode */
	user_dma_handler_t in_handler;
				    /**< associated ISR, with one argument (irqnum), see types.h */
	user_dma_handler_t out_handler;
				    /**< associated ISR, with one argument (irqnum), see types.h */
} dma_t;


/**
** \brief DMA shared memory access mode
*/
typedef enum {
  DMA_SHM_ACCESS_RD, /**< The DMA SHR is a DMA source address only */
  DMA_SHM_ACCESS_WR, /**< The DMA SHR is a DMA destination address only */
} dma_shm_access_t;

/**
** \brief DMA shared memory structure
** This structure host the DMA hared memory informations passed to the
** kernel when declaring a DMA SHM with another task
*/
typedef struct {
  e_task_id        target;  /**< target task authorized to initiate a DMA transfer to/from this region */
  e_task_id        source;  /**< Your own id */
  uint32_t         address; /**< the region base address */
  uint16_t         size;    /**< the region size (in bytes) */
  dma_shm_access_t mode;    /**< the region access rights */
} dma_shm_t;

#endif				/*!EXPORTED_DMAS_H_ */
