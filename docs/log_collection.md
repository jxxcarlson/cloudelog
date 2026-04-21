I would like now to introduce the notion of a "log collection."  This is a list of related logs that are grouped together for convenience sake and for coherence of purpose. For example, a piano student may have log collection consisting of logs

  - Sight reading (quantity: Float, unit : minutes)
  - Harmony (quantity: Float, unit : minutes)
  - Improvisation (quantity: Float, unit : minutes)
  - Repertoire (quantity: Float, unit : minutes)

  A snippet from the log might look like
  
  ------------------------------------------
  May 2, 2023
  -----------
  Sight reading | 15 min | Clementi onatina 
  Harmony | 5 min | 
  Improvisation | 10 min | Blues in C
  Repertoire | 30 min | Bach, Sinfonia 2
  ------------------------------------------
  May 3, 2020
  -----------
  ...
  
  The summary should give individual and total statistics, e.g. stats for Sight reading, for Harmony, and so forth, as well as for Sight reading + Harmony + ...
If there are logs with different units, total statistics make sense only for
subsets with the same units and should be grouped as such.

  
