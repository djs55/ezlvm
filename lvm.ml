(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Common

let make_temp_volume () =
  let path = Filename.temp_file Sys.argv.(0) "volume" in
  ignore_string (Common.run "dd" [ "if=/dev/zero"; "of=" ^ path; "seek=1024"; "bs=1M"; "count=1"]);
  finally
    (fun () ->
      ignore_string (Common.run "losetup" [ "-f"; path ]);
      (* /dev/loop0: [fd00]:1973802 (/tmp/SR.createc04251volume) *)
      let line = Common.run "losetup" [ "-j"; path ] in
      try
        let i = String.index line ' ' in
        String.sub line 0 (i - 1)
      with e ->
        error "Failed to parse output of losetup -j: [%s]" line;
        ignore_string (Common.run "losetup" [ "-d"; path ]);
        failwith (Printf.sprintf "Failed to parse output of losetup -j: [%s]" line)
    ) (fun () -> rm_f path)

let remove_temp_volume volume =
  ignore_string (Common.run "losetup" [ "-d"; volume ])

let vgcreate vg_name = function
  | [] -> failwith "I need at least 1 physical device to create a volume group"
  | d :: ds as devices ->
    List.iter
      (fun dev ->
        (* First destroy anything already on the device *)
        ignore_string (run "dd" [ "if=/dev/zero"; "of=" ^ dev; "bs=512"; "count=4" ]);
        ignore_string (run "pvcreate" [ "--metadatasize"; "10M"; dev ])
      ) devices;

    (* Create the VG on the first device *)
    ignore_string (run "vgcreate" [ vg_name; d ]);
    List.iter (fun dev -> ignore_string (run "vgextend" [ vg_name; dev ])) ds;
    ignore_string (run "vgchange" [ "-an"; vg_name ])

let lvcreate vg_name lv_name bytes =
  let size_mb = Int64.to_string (Int64.div (Int64.add 1048575L bytes) (1048576L)) in
  ignore_string (Common.run "lvcreate" [ "-L"; size_mb; "-n"; lv_name; "vg_name"; "-Z"; "n" ])
