module SegmentedMsg {
  use Reflection;
  use Errors;
  use SegmentedArray;
  use ServerErrorStrings;
  use ServerConfig;
  use MultiTypeSymbolTable;
  use MultiTypeSymEntry;
  use RandArray;
  use IO;
  use GenSymIO only jsonToPdArray;

  private config const DEBUG = false;

  proc randomStringsMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
      var pn = Reflection.getRoutineName();
      var (lenStr, dist, charsetStr, arg1str, arg2str)
          = payload.decode().splitMsgToTuple(5);
      var len = lenStr: int;
      var charset = str2CharSet(charsetStr);
      var segName = st.nextName();
      var valName = st.nextName();
      var repMsg: string;
      select dist.toLower() {
          when "uniform" {
              var minLen = arg1str:int;
              var maxLen = arg2str:int;
              // Lengths + 2*segs + 2*vals (copied to SymTab)
              overMemLimit(8*len + 16*len + (maxLen + minLen)*len);
              var (segs, vals) = newRandStringsUniformLength(len, minLen, maxLen, charset);
              var segEntry = new shared SymEntry(segs);
              var valEntry = new shared SymEntry(vals);
              st.addEntry(segName, segEntry);
              st.addEntry(valName, valEntry);
              repMsg = 'created ' + st.attrib(segName) + '+created ' + st.attrib(valName);
          }
          when "lognormal" {
              var logMean = arg1str:real;
              var logStd = arg2str:real;
              // Lengths + 2*segs + 2*vals (copied to SymTab)
              overMemLimit(8*len + 16*len + exp(logMean + (logStd**2)/2):int*len);
              var (segs, vals) = newRandStringsLogNormalLength(len, logMean, logStd, charset);
              var segEntry = new shared SymEntry(segs);
              var valEntry = new shared SymEntry(vals);
              st.addEntry(segName, segEntry);
              st.addEntry(valName, valEntry);
              repMsg = 'created ' + st.attrib(segName) + '+created ' + st.attrib(valName);
          }
          otherwise { 
              repMsg = notImplementedError(pn, dist);       
              writeln(generateErrorContext(
                                     msg=repMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));          
          }
      }
      return repMsg;
  }

  proc segmentLengthsMsg(cmd: string, payload: bytes, 
                                          st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var (objtype, segName, valName) = payload.decode().splitMsgToTuple(3);
    var rname = st.nextName();
    select objtype {
      when "str" {
        var strings = new owned SegString(segName, valName, st);
        var lengths = st.addEntry(rname, strings.size, int);
        // Do not include the null terminator in the length
        lengths.a = strings.getLengths() - 1;
      }
      otherwise {
          var errorMsg = notImplementedError(pn, "%s".format(objtype));
          writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));                   
          return errorMsg;
      }
    }
    return "created "+st.attrib(rname);
  }

  proc segmentedEfuncMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    var (subcmd, objtype, segName, valName, valtype, valStr,
         idStr, kpStr, lStr, jsonStr) = payload.decode().splitMsgToTuple(10);
    select (objtype, valtype) {
    when ("str", "str") {
      var strings = new owned SegString(segName, valName, st);
      select subcmd {
        when "contains" {
          var json = jsonToPdArray(valStr, 1);
          var val = json[json.domain.low];
          var rname = st.nextName();
          var truth = st.addEntry(rname, strings.size, bool);
          truth.a = strings.substringSearch(val, SearchMode.contains);
          repMsg = "created "+st.attrib(rname);
        }
        when "startswith" {
          var json = jsonToPdArray(valStr, 1);
          var val = json[json.domain.low];
          var rname = st.nextName();
          var truth = st.addEntry(rname, strings.size, bool);
          truth.a = strings.substringSearch(val, SearchMode.startsWith);
          repMsg = "created "+st.attrib(rname);
        }
        when "endswith" {
          var json = jsonToPdArray(valStr, 1);
          var val = json[json.domain.low];
          var rname = st.nextName();
          var truth = st.addEntry(rname, strings.size, bool);
          truth.a = strings.substringSearch(val, SearchMode.endsWith);
          repMsg = "created "+st.attrib(rname);
        }
        when "peel" {
          var times = valStr:int;
          var includeDelimiter = (idStr.toLower() == "true");
          var keepPartial = (kpStr.toLower() == "true");
          var left = (lStr.toLower() == "true");
          var json = jsonToPdArray(jsonStr, 1);
          var val = json[json.domain.low];
          var loname = st.nextName();
          var lvname = st.nextName();
          var roname = st.nextName();
          var rvname = st.nextName();
          select (includeDelimiter, keepPartial, left) {
          when (false, false, false) {
            var (lo, lv, ro, rv) = strings.peel(val, times, false, false, false);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (false, false, true) {
            var (lo, lv, ro, rv) = strings.peel(val, times, false, false, true);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (false, true, false) {
            var (lo, lv, ro, rv) = strings.peel(val, times, false, true, false);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (false, true, true) {
            var (lo, lv, ro, rv) = strings.peel(val, times, false, true, true);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (true, false, false) {
            var (lo, lv, ro, rv) = strings.peel(val, times, true, false, false);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (true, false, true) {
            var (lo, lv, ro, rv) = strings.peel(val, times, true, false, true);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (true, true, false) {
            var (lo, lv, ro, rv) = strings.peel(val, times, true, true, false);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } when (true, true, true) {
            var (lo, lv, ro, rv) = strings.peel(val, times, true, true, true);
            st.addEntry(loname, new shared SymEntry(lo));
            st.addEntry(lvname, new shared SymEntry(lv));
            st.addEntry(roname, new shared SymEntry(ro));
            st.addEntry(rvname, new shared SymEntry(rv));
          } otherwise {
              var errorMsg = notImplementedError(pn, 
                               "subcmd: %s, (%s, %s)".format(subcmd, objtype, valtype));
              writeln(generateErrorContext(
                                     msg=repMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));   
              return errorMsg;                            
              }
          }
          repMsg = "created %s+created %s+created %s+created %s".format(st.attrib(loname),
                                                                        st.attrib(lvname),
                                                                        st.attrib(roname),
                                                                        st.attrib(rvname));
        }
        otherwise {
            var errorMsg = notImplementedError(pn, 
                              "subcmd: %s, (%s, %s)".format(subcmd, objtype, valtype));
            writeln(generateErrorContext(
                                     msg=repMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));    
            return errorMsg;                                          
        }
      }
    }
    otherwise {
        var errorMsg = notImplementedError(pn, "(%s, %s)".format(objtype, valtype));
        writeln(generateErrorContext(
                                     msg=repMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));  
        return errorMsg;       
      }
    }
    return repMsg;
  }

  proc segmentedHashMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    var (objtype, segName, valName) = payload.decode().splitMsgToTuple(3);
    select objtype {
        when "str" {
            var strings = new owned SegString(segName, valName, st);
            var hashes = strings.hash();
            var name1 = st.nextName();
            var hash1 = st.addEntry(name1, hashes.size, int);
            var name2 = st.nextName();
            var hash2 = st.addEntry(name2, hashes.size, int);
            forall (h, h1, h2) in zip(hashes, hash1.a, hash2.a) {
                (h1,h2) = h:(int,int);
            }
            return "created " + st.attrib(name1) + "+created " + st.attrib(name2);
        }
        otherwise {
            var errorMsg = notImplementedError(pn, objtype);
            writeln(generateErrorContext(
                                     msg=repMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
            return errorMsg;
        }
    }
  }


  /*
   * Assigns a segIntIndex, sliceIndex, or pdarrayIndex to the incoming payload
   * consisting of a sub-command, object type, offset SymTab key, array SymTab
   * key, and index value for the incoming payload.
   * 
   * Note: the sub-command indicates the index type which can be one of the following:
   * 1. intIndex : setIntIndex
   * 2. sliceIndex : segSliceIndex
   * 3. pdarrayIndex : segPdarrayIndex
  */ 
  proc segmentedIndexMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    // 'subcmd' is the type of indexing to perform
    // 'objtype' is the type of segmented array
    var (subcmd, objtype, rest) = payload.decode().splitMsgToTuple(3);
    var fields = rest.split();
    var args: [1..#fields.size] string = fields; // parsed by subroutines
    writeln("subcmd: %s objtype: %s rest: %s".format(subcmd,objtype,rest));
    try {
        select subcmd {
            when "intIndex" {
                return segIntIndex(objtype, args, st);
            }
            when "sliceIndex" {
                return segSliceIndex(objtype, args, st);
            }
            when "pdarrayIndex" {
                return segPdarrayIndex(objtype, args, st);
            }
            otherwise {
                var errorMsg = "Error: in %s, nknown subcommand %s".format(pn, subcmd);
                writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="UknownSubcommandError")); 
               return errorMsg;
            }
        }
    } catch e: OutOfBoundsError {
        var errorMsg = "Error: index out of bounds";
        writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="OutOfBoundsError")); 
        return errorMsg;
    } catch {
        var errorMsg = "Error: unknown cause";
        writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="UnknownError")); 
        return errorMsg;
    }
  }
 
  /*
  Returns the object corresponding to the index
  */ 
  proc segIntIndex(objtype: string, args: [] string, 
                                         st: borrowed SymTab): string throws {
      var pn = Reflection.getRoutineName();
      select objtype {
          when "str" {
              // Make a temporary strings array
              var strings = new owned SegString(args[1], args[2], st);
              // Parse the index
              var idx = args[3]:int;
              // TO DO: in the future, we will force the client to handle this
              idx = convertPythonIndexToChapel(idx, strings.size);
              var s = strings[idx];
              return "item %s %jt".format("str", s);
          }
          otherwise { 
              var errorMsg = notImplementedError(pn, objtype); 
              writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
             return errorMsg;                          
          }
      }
  }

  /* Allow Python-style negative indices. */
  proc convertPythonIndexToChapel(pyidx: int, high: int): int {
    var chplIdx: int;
    if (pyidx < 0) {
      chplIdx = high + 1 + pyidx;
    } else {
      chplIdx = pyidx;
    }
    return chplIdx;
  }

  proc segSliceIndex(objtype: string, args: [] string, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    select objtype {
      when "str" {
        // Make a temporary string array
        var strings = new owned SegString(args[1], args[2], st);
        // Parse the slice parameters
        var start = args[3]:int;
        var stop = args[4]:int;
        var stride = args[5]:int;
        // Only stride-1 slices are allowed for now
        if (stride != 1) { 
            var errorMsg = notImplementedError(pn, "stride != 1"); 
            writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
            return errorMsg;
        }
        // TO DO: in the future, we will force the client to handle this
        var slice: range(stridable=true) = convertPythonSliceToChapel(start, stop, stride);
        var newSegName = st.nextName();
        var newValName = st.nextName();
        // Compute the slice
        var (newSegs, newVals) = strings[slice];
        // Store the resulting offsets and bytes arrays
        var newSegsEntry = new shared SymEntry(newSegs);
        var newValsEntry = new shared SymEntry(newVals);
        st.addEntry(newSegName, newSegsEntry);
        st.addEntry(newValName, newValsEntry);
        return "created " + st.attrib(newSegName) + " +created " + st.attrib(newValName);
      }
      otherwise {
          var errorMsg = notImplementedError(pn, objtype);
          writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
          return errorMsg;          
        }
      }
  }

  proc convertPythonSliceToChapel(start:int, stop:int, stride:int=1): range(stridable=true) {
    var slice: range(stridable=true);
    // convert python slice to chapel slice
    // backwards iteration with negative stride
    if  (start > stop) & (stride < 0) {slice = (stop+1)..start by stride;}
    // forward iteration with positive stride
    else if (start <= stop) & (stride > 0) {slice = start..(stop-1) by stride;}
    // BAD FORM start < stop and stride is negative
    else {slice = 1..0;}
    return slice;
  }

  proc segPdarrayIndex(objtype: string, args: [] string, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var newSegName = st.nextName();
    var newValName = st.nextName();
    select objtype {
      when "str" {
        var strings = new owned SegString(args[1], args[2], st);
        var iname = args[3];
        var gIV: borrowed GenSymEntry = st.lookup(iname);
        select gIV.dtype {
          when DType.Int64 {
            var iv = toSymEntry(gIV, int);
            var (newSegs, newVals) = strings[iv.a];
            var newSegsEntry = new shared SymEntry(newSegs);
            var newValsEntry = new shared SymEntry(newVals);
            st.addEntry(newSegName, newSegsEntry);
            st.addEntry(newValName, newValsEntry);
          }
          when DType.Bool {
            var iv = toSymEntry(gIV, bool);
            var (newSegs, newVals) = strings[iv.a];
            var newSegsEntry = new shared SymEntry(newSegs);
            var newValsEntry = new shared SymEntry(newVals);
            st.addEntry(newSegName, newSegsEntry);
            st.addEntry(newValName, newValsEntry);
          }
          otherwise {return notImplementedError(pn,
                                                "("+objtype+","+dtype2str(gIV.dtype)+")");}
          }
      }
      otherwise {return notImplementedError(pn, objtype);}
      }
    return "created " + st.attrib(newSegName) + "+created " + st.attrib(newValName);
  }

  proc segBinopvvMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    var (op,
         // Type and attrib names of left segmented array
         ltype, lsegName, lvalName,
         // Type and attrib names of right segmented array
         rtype, rsegName, rvalName, leftStr, jsonStr)
           = payload.decode().splitMsgToTuple(9);
    select (ltype, rtype) {
    when ("str", "str") {
      var lstrings = new owned SegString(lsegName, lvalName, st);
      var rstrings = new owned SegString(rsegName, rvalName, st);
      select op {
        when "==" {
          var rname = st.nextName();
          var e = st.addEntry(rname, lstrings.size, bool);
          e.a = (lstrings == rstrings);
          repMsg = "created " + st.attrib(rname);
        }
        when "!=" {
          var rname = st.nextName();
          var e = st.addEntry(rname, lstrings.size, bool);
          e.a = (lstrings != rstrings);
          repMsg = "created " + st.attrib(rname);
        }
        when "stick" {
          var left = (leftStr.toLower() != "false");
          var json = jsonToPdArray(jsonStr, 1);
          const delim = json[json.domain.low];
          var oname = st.nextName();
          var vname = st.nextName();
          if left {
            var (newOffsets, newVals) = lstrings.stick(rstrings, delim, false);
            st.addEntry(oname, new shared SymEntry(newOffsets));
            st.addEntry(vname, new shared SymEntry(newVals));
          } else {
            var (newOffsets, newVals) = lstrings.stick(rstrings, delim, true);
            st.addEntry(oname, new shared SymEntry(newOffsets));
            st.addEntry(vname, new shared SymEntry(newVals));
          }
          repMsg = "created %s+created %s".format(st.attrib(oname), st.attrib(vname));
          if DEBUG {writeln(repMsg);}
        }
        otherwise {return notImplementedError(pn, ltype, op, rtype);}
        }
    }
    otherwise {return unrecognizedTypeError(pn, "("+ltype+", "+rtype+")");} 
    }
    return repMsg;
  }

  proc segBinopvsMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    var (op, objtype, segName, valName, valtype, encodedVal)
          = payload.decode().splitMsgToTuple(6);
    var json = jsonToPdArray(encodedVal, 1);
    var value = json[json.domain.low];
    var rname = st.nextName();
    select (objtype, valtype) {
    when ("str", "str") {
      var strings = new owned SegString(segName, valName, st);
      select op {
        when "==" {
          var e = st.addEntry(rname, strings.size, bool);
          e.a = (strings == value);
        }
        when "!=" {
          var e = st.addEntry(rname, strings.size, bool);
          e.a = (strings != value);
        }
        otherwise {return notImplementedError(pn, objtype, op, valtype);}
        }
    }
    otherwise {return unrecognizedTypeError(pn, "("+objtype+", "+valtype+")");} 
    }
    return "created " + st.attrib(rname);
  }

  proc segIn1dMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
    var pn = Reflection.getRoutineName();
    var repMsg: string;
    var (mainObjtype, mainSegName, mainValName, testObjtype, testSegName,
         testValName, invertStr) = payload.decode().splitMsgToTuple(7);
    var invert: bool;
    if invertStr == "True" {invert = true;}
    else if invertStr == "False" {invert = false;}
    else {return "Error: Invalid argument in %s: %s (expected True or False)".format(pn, invertStr);}
    
    var rname = st.nextName();
    select (mainObjtype, testObjtype) {
    when ("str", "str") {
      var mainStr = new owned SegString(mainSegName, mainValName, st);
      var testStr = new owned SegString(testSegName, testValName, st);
      var e = st.addEntry(rname, mainStr.size, bool);
      if invert {
        e.a = !in1d(mainStr, testStr);
      } else {
        e.a = in1d(mainStr, testStr);
      }
    }
    otherwise {
        var errorMsg = unrecognizedTypeError(pn, "("+mainObjtype+", "+testObjtype+")");
        writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
        return errorMsg;            
      }
    }
    return "created " + st.attrib(rname);
  }

  proc segGroupMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
      var pn = Reflection.getRoutineName();
      var (objtype, segName, valName) = payload.decode().splitMsgToTuple(3);
      var rname = st.nextName();
      select (objtype) {
          when "str" {
              var strings = new owned SegString(segName, valName, st);
              var iv = st.addEntry(rname, strings.size, int);
              iv.a = strings.argGroup();
          }
          otherwise {
              var errorMsg = notImplementedError(pn, "("+objtype+")");
              writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError")); 
              return errorMsg;            
          }
      }
      return "created " + st.attrib(rname);
  }
}
