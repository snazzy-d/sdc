# Size Classes

Dalloc uses size classes of the form `[4, 5, 6, 7] * 2^n` which provides 2 bits
of precision. This strategy is similar to the one used by jemalloc, as it turns
out to be a good tradeof in practice.

In practice, dalloc tries to use the right amount of memory for each allocations
to limit overhead, but it would be wasteful to track all possible allocations
sizes, so we use size classes as an aproximation. This performs well in
practice, as, even though we do not always pick the best fit, we also avoid
leaving behing a ton of very small range that will be hard to use later and
cause fragmentation.

# Slabs

For small allocation, we first allocate a slab. A slab is a large allocation of
a set number of pages which contains a certain number of small allocations.

We sometime need to compute the index of an element within a slab. The naive way
to do this uses a division, however, such a division is very expensive to
compute. In order to speed things up, we compute the division via
`(index * multiplier) >> shift` with carefully chosen multipliers and shifts
values. These values were found using the `bin/tools/finddivisor` utility.

For each small size class, the properties of the slab can be found in the table
bellow:

| Size class | Element size | Pages | Slot count | Multiplier | Shift | Appendable / Destructible | Dense |
| ---------: | -----------: | ----: | ---------: | ---------: | ----: | :-----------------------: | :---: |
|          0 |            8 |     1 |        512 |      32768 |    18 |             N             |   Y   |
|          1 |           16 |     1 |        256 |      32768 |    19 |             Y             |   Y   |
|          2 |           24 |     3 |        512 |      21846 |    19 |             N             |   Y   |
|          3 |           32 |     1 |        128 |      32768 |    20 |             Y             |   Y   |
|          4 |           40 |     5 |        512 |      26215 |    20 |             N             |   Y   |
|          5 |           48 |     3 |        256 |      21846 |    20 |             Y             |   Y   |
|          6 |           56 |     7 |        512 |      18725 |    20 |             N             |   Y   |
|          7 |           64 |     1 |         64 |      32768 |    21 |             Y             |   Y   |
|          8 |           80 |     5 |        256 |      26215 |    21 |             Y             |   Y   |
|          9 |           96 |     3 |        128 |      21846 |    21 |             Y             |   Y   |
|         10 |          112 |     7 |        256 |      18725 |    21 |             Y             |   Y   |
|         11 |          128 |     1 |         32 |      32768 |    22 |             Y             |   Y   |
|         12 |          160 |     5 |        128 |      26215 |    22 |             Y             |   Y   |
|         13 |          192 |     3 |         64 |      21846 |    22 |             Y             |   Y   |
|         14 |          224 |     7 |        128 |      18725 |    22 |             Y             |   Y   |
|         15 |          256 |     1 |         16 |      32768 |    23 |             Y             |   N   |
|         16 |          320 |     5 |         64 |      26215 |    23 |             Y             |   Y   |
|         17 |          384 |     3 |         32 |      21846 |    23 |             Y             |   Y   |
|         18 |          448 |     7 |         64 |      18725 |    23 |             Y             |   Y   |
|         19 |          512 |     1 |          8 |      32768 |    24 |             Y             |   N   |
|         20 |          640 |     5 |         32 |      26215 |    24 |             Y             |   Y   |
|         21 |          768 |     3 |         16 |      21846 |    24 |             Y             |   N   |
|         22 |          896 |     7 |         32 |      18725 |    24 |             Y             |   Y   |
|         23 |         1024 |     1 |          4 |      32768 |    25 |             Y             |   N   |
|         24 |         1280 |     5 |         16 |      26215 |    25 |             Y             |   N   |
|         25 |         1536 |     3 |          8 |      21846 |    25 |             Y             |   N   |
|         26 |         1792 |     7 |         16 |      18725 |    25 |             Y             |   N   |
|         27 |         2048 |     1 |          2 |      32768 |    26 |             Y             |   N   |
|         28 |         2560 |     5 |          8 |      26215 |    26 |             Y             |   N   |
|         29 |         3072 |     3 |          4 |      21846 |    26 |             Y             |   N   |
|         30 |         3584 |     7 |          8 |      18725 |    26 |             Y             |   N   |
|         31 |         4096 |     1 |          1 |      32768 |    27 |             Y             |   N   |
|         32 |         5120 |     5 |          4 |      26215 |    27 |             Y             |   N   |
|         33 |         6144 |     3 |          2 |      21846 |    27 |             Y             |   N   |
|         34 |         7168 |     7 |          4 |      18725 |    27 |             Y             |   N   |
|         35 |         8192 |     2 |          1 |      32768 |    28 |             Y             |   N   |
|         36 |        10240 |     5 |          2 |      26215 |    28 |             Y             |   N   |
|         37 |        12288 |     3 |          1 |      21846 |    28 |             Y             |   N   |
|         38 |        14336 |     7 |          2 |      18725 |    28 |             Y             |   N   |
