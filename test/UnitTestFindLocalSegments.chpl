prototype module UnitTestFindSegments
{
    config const NVALS = 2**13;
    config const LEN = 2**20;
    config const filename = "UnitTestFindLocalSegments.array";

    use TestBase;
    
    use RandMsg;
    use IndexingMsg;
    use ReductionMsg;
    use ArgSortMsg;
    use FindSegmentsMsg;

    proc writeIntArray(a:[?D] int, filename:string) {
      var f = try! open(filename, iomode.cw);
      var w = try! f.writer(kind=ionative);
      try! w.write(D.size);
      try! w.write(a);
      try! w.close();
      try! f.close();
    }
    
    proc main() {
        writeln("Unit Test for findLocalSegmentsMsg");
        var st = new owned SymTab();

        var reqMsg: string;
        var repMsg: string;

        // create an array filled with random int64 returned in symbol table
        var aname = nameForRandintMsg(LEN, DType.Int64, 0, NVALS, st);

        // sort it and return iv in symbol table
        var cmd = "localArgsort";
        var orig = toSymEntry(st.lookup(aname), int);
        writeIntArray(orig.a, filename+".original");
        reqMsg = try! "%s %s".format(cmd, aname);
        var t1 = Time.getCurrentTime();
        repMsg = localArgsortMsg(reqMsg, st);
        writeln("time = ",Time.getCurrentTime() - t1,"sec"); try! stdout.flush();
        writeln(repMsg);

        // Get back the iv and apply to return locally sorted keys
        var ivname = parseName(repMsg); // get name from argsort reply msg
        var iv = toSymEntry(st.lookup(ivname), int);
        writeIntArray(iv.a, filename+".permutation");
        cmd = "[pdarray]";
        reqMsg = try! "%s %s %s".format(cmd, aname, ivname);
        t1 = Time.getCurrentTime();
        repMsg = pdarrayIndexMsg(reqMsg, st);
        writeln("time = ",Time.getCurrentTime() - t1,"sec"); try! stdout.flush();
        writeln(repMsg);
        var sortedname = parseName(repMsg);
        var sorted = toSymEntry(st.lookup(sortedname), int);
        writeIntArray(sorted.a, filename+".permuted");

        // use array and iv to find local segments
        cmd = "findLocalSegments";
        reqMsg = try! "%s %s".format(cmd, aname);
        writeln(reqMsg);
        t1 = Time.getCurrentTime();
        repMsg = findLocalSegmentsMsg(reqMsg, st);
        writeln("time = ",Time.getCurrentTime() - t1,"sec"); try! stdout.flush();
        writeln(repMsg);

        // check for correct local segmentation of result
        var (segname, ukeysname) = parseTwoNames(repMsg);
        var segs = toSymEntry(st.lookup(segname), int);
        var ukeys = toSymEntry(st.lookup(ukeysname), int);
        writeIntArray(segs.a, filename+".segments");
        writeIntArray(ukeys.a, filename+".unique_keys");
        writeln("Checking if correctly segmented...");
        t1 = Time.getCurrentTime();
        var answer = is_locally_segmented(sorted.a, segs.a, ukeys.a);
        writeln("time = ",Time.getCurrentTime() - t1,"sec"); try! stdout.flush();
        writeln("ANSWER >>> ",answer:string," <<<");
    }

    proc is_locally_segmented(sorted, segs, ukeys):bool {
      var globalTruths:[LocaleSpace] bool;
      var valsChecked: atomic int;
      coforall loc in Locales {
        on loc {
          var hereCorrect: bool;
          var locChecked = 0;
          var myKeys = ukeys;
          local {
            var segDom = segs.localSubdomain();
            var truths:[segDom] bool;
            forall segInd in segDom with (ref truths, + reduce locChecked) {
              var key = myKeys[segInd - segDom.low];
              var low = segs[segInd];
              var high: int;
              if (segInd == segDom.high) || (segs[segInd + 1] > sorted.localSubdomain().high) {
                high = sorted.localSubdomain().high;
              } else {
                high = segs[segInd + 1] - 1;
              }
              if (high >= low) {
                truths[segInd] = && reduce (sorted[low..high] == key);
              } else {
                truths[segInd] = true;
              }
              locChecked += high - low + 1;
            }
            hereCorrect = && reduce truths;
          }
          globalTruths[here.id] = hereCorrect;
          valsChecked.add(locChecked);
        }
      }
      return (&& reduce globalTruths) && (valsChecked.read() == sorted.size);
    }
}

