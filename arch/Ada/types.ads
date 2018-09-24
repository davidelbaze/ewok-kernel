-- Here are the general restriction on Ada implementation.
-- Some are automatically added when activated SPARK mode in SPARK modules
-- no RTE double stacking
pragma restrictions (no_secondary_stack);
-- no elaboration code must be required at start
pragma restrictions (no_elaboration_code);
-- ... and no finalization (cleaning of elaboration)
pragma restrictions (no_finalization);
-- no exception should arise
pragma restrictions (no_exception_handlers);
-- no recursion call
pragma restrictions (no_recursion);
-- no wide chars
pragma restrictions (no_wide_characters);


with system;
with ada.unchecked_conversion;
with interfaces;  use interfaces;

package types
   with SPARK_Mode => On
is

   KBYTE  : constant := 2 ** 10;
   MBYTE  : constant := 2 ** 20;
   GBYTE  : constant := 2 ** 30;

   subtype byte  is unsigned_8;
   subtype short is unsigned_16;
   subtype word  is unsigned_32;

   subtype milliseconds is unsigned_64;
   subtype microseconds is unsigned_64;

   subtype system_address is unsigned_32;

   function to_address is new ada.unchecked_conversion
     (system_address, system.address);

   function to_system_address is new ada.unchecked_conversion
     (system.address, system_address);

   function to_word is new ada.unchecked_conversion
     (system.address, word);

   function to_unsigned_32 is new ada.unchecked_conversion
     (system.address, unsigned_32);

   --
   -- u8, u16 vers u32
   --

   pragma warnings (off);

   function to_unsigned_32 is new ada.unchecked_conversion
     (unsigned_8, unsigned_32);

   function to_unsigned_32 is new ada.unchecked_conversion
     (unsigned_16, unsigned_32);

   pragma warnings (on);

   type byte_array  is array (unsigned_32 range <>) of byte;
   for byte_array'component_size use byte'size;

   type short_array is array (unsigned_32 range <>) of short;
   for short_array'component_size use short'size;

   type word_array  is array (unsigned_32 range <>) of word;
   for word_array'component_size use word'size;

   type unsigned_8_array is new byte_array;
   type unsigned_16_array is new short_array;
   type unsigned_32_array is new word_array;


   nul : constant character := character'First;


   type bit     is mod 2**1  with size => 1;
   type bits_2  is mod 2**2  with size => 2;
   type bits_3  is mod 2**3  with size => 3;
   type bits_4  is mod 2**4  with size => 4;
   type bits_5  is mod 2**5  with size => 5;
   type bits_6  is mod 2**6  with size => 6;
   type bits_7  is mod 2**7  with size => 7;

   type bits_9  is mod 2**9  with size => 9;
   type bits_10 is mod 2**10 with size => 10;

   type bits_24 is mod 2**24 with size => 24;

   type bits_27 is mod 2**27 with size => 27;

   type bool is new boolean with size => 1;
   for bool use (true => 1, false => 0);

   function to_bit
     (u : unsigned_8) return types.bit;

   function to_bit
     (u : unsigned_32) return types.bit;

end types;
