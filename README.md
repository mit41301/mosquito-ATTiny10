# tiny10 mosquito
 What has six legs and is very annoying? Well, lots of things I guess.  But now there is one based on the 6-pin ATtiny10 microcontroller. 

<img width="620" height="300" alt="image" src="https://github.com/user-attachments/assets/da7a8683-95e4-4595-9cb1-de77475bdb99" />

## Basically it does this: 
1. Lies in wait until it detects a remote control signal.
2. Records the signal and waits for 30 seconds.
3. Resends the signal.
4. Plays a little tune you may have heard before.

##   How to make one
On the off chance that you actually want one of these, here is how to make one. The parts you need include:
1. ATtiny10
2. little circuit board - I was lucky to find a breakout board with some pads on the bottom
3. IR receiver - 38kHz is probably the most common
4. piezo speaker
5. IR LED - 940nm or so
6. 3.6V lithium button cell - or any other power source you have
7. power capacitor - I used a 100uF electrolytic
8. resistors - 100, 1k, 10k x2

   But wait! Before you go putting it all together, remember that you have to be able to program the thing. This hardware setup is not programmer friendly, so make sure you have the program on the chip before soldering it all. I soldered the chip onto the breakout board, programmed it, then put the rest on. 

Writing the code presented a variety of challenges. I repeatedly went over the 1024 byte limit and had to optimize things a bit. Also, with only 32 bytes of ram I had to be very careful. I ended up using 22 of those bytes to hold the timing and sequence information for the IR signal. The stack didn't use more than 8 bytes anywhere, which left me with 2 extra peace of mind bytes.

The assembly code is included at the end of this page. It is easy to change the tune or delay intervals, but you will have to dig your way through the code to do so. Some things to note are:
- The tiny10 goes into power-down sleep mode while it waits, so it won't burn through your battery.
- It will record up to 64 bits plus a header pulse as long as nothing is longer than about 12ms. This covers any of the common remote protocols, as far as I know.
- It records four timing values: header on, header off, long on, short on, long off, short off.
