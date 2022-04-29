# adler32-sse2
Adler32 implementation used in Alpha64. Includes a demonstrational commmand-line frontend.

```
% hyperfine './adler32 /home/palaiologos/workspace/RADS.7z'
Benchmark 1: ./adler32 /home/palaiologos/workspace/RADS.7z
  Time (mean ± σ):     442.5 ms ±   3.4 ms    [User: 309.1 ms, System: 133.1 ms]
  Range (min … max):   437.9 ms … 448.3 ms    10 runs
% wc -c /home/palaiologos/workspace/RADS.7z
4355492375 /home/palaiologos/workspace/RADS.7z
```

With a mean runtime of 310ms on a 4'355'492'375 byte file, the program can process around 14'049'975'403 bytes per second (~ 13GiB/s) on my Ryzen 9 testing box.

The checksum tool is 1015 bytes large:

```
% wc -c adler
1015 adler
```

Build using `fasm adler32.asm`
