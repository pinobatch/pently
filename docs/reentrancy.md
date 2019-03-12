Reentrancy
==========

NES programs have two "threads" of execution: a main program and a
handler for the non-maskable interrupt (NMI) that runs at the start
of each vertical blanking (vblank) period.  On the NES, a sound
driver can be run within the main thread or the NMI handler.  Many
programmers recommend running the sound driver at the end of NMI,
after all video memory updates have finished, in order to keep music
from lagging even when the game lags.  This invites two problems,
with solutions of varying complexity.

The first problem with audio in NMI is data races.  The subroutine
to start a sound effect or change the music works by updating data
structures owned by the sound driver.  If the NMI happens right in
the middle of these updates, the sound driver could get confused and
show hard-to-predict behavior.

The second problem is saving and restoring the state of the mapper.
It's common to put audio in its own bank to free up room in the fixed
bank for parts of the program that read from more than one bank.
If the mapper register that chooses the bank for each window has its
own address, this is fairly easy.  This is true of discrete mappers,
such as UNROM, as well as select ASIC mappers, such as Konami's VRC
series.  It's less straightforward for mappers that require multiple
steps to change a bank, as NMI cannot necessarily tell which step the
main thread was on.  These include MMC1 with its serial load and
(to a lesser extent) MMC3 and FME-7 with their address/data paradigm.

One way to work around data races involves passing all play commands
through a data structure free of races, such as a lock-free circular
list of commands from the main thread to the sound driver.  The main
thread adds play commands to the queue, and the NMI removes them and
calls `pently_start_music` and `pently_start_sound` as needed,
followed by `pently_update`.

A second way is to have the main thread do all the work and count the
frames by which audio is behind.

    nmi_handler:
        inc nmis
        ; Omitted: Optionally push updates to video memory
        rti
    
    ; This is called in the main thread
    catchup_audio:
        lda music_last_nmis
        cmp nmis
        beq @no_catchup
        ; Omitted: Save current PRG bank
        ; Omitted: Switch to audio bank
    @catchup_loop:
        jsr pently_update
        inc music_last_nmis
        lda music_last_nmis
        cmp nmis
        bne @catchup_loop
        ; Omitted: Restore previous PRG bank
    @no_catchup:
        rts

The catch-up strategy causes overall tempo to remain constant even
if updates lag.  One drawback of catch-up is that particularly long
operations, such as decompressing a CHR set and associated tilemap
to video memory, may cause envelopes to get stuck momentarily.
The program can mitigate this by calling catch-up at strategic
points in the operation.

A third way is to put a mutex around the main thread's updates,
updated using the 6502's atomic `inc` and `dec` instructions.
The NMI handler looks at whether this mutex is acquired, and if so,
it sets a "retry" flag instead of calling the sound driver.  Before
releasing the mutex, the main thread looks at the retry flag and runs
the audio driver again if it is set, in order to catch up for what
the mutex blocked.

The best synchronization approach for any given game depends on the
structure of the game, the size in bytes of the soundtrack, and which
mapper is used.
