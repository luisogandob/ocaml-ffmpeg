(* Options *)
type opt_val = [ `String of string | `Int of int | `Float of float ]
type opts = (string, opt_val) Hashtbl.t

(* Line *)
type input
type output

(* Container *)
type 'a container

(** {1 Media types} *)

type audio = [ `Audio ]
type video = [ `Video ]
type subtitle = [ `Subtitle ]

type media_type =
  [ audio | video | subtitle | `Unknown | `Data | `Attachment | `Nb ]

(* Format *)
type ('line, 'media) format

(* Frame *)
type 'media frame

external frame_pts : _ frame -> Int64.t = "ocaml_avutil_frame_pts"

external frame_set_pts : _ frame -> Int64.t -> unit
  = "ocaml_avutil_frame_set_pts"

type error =
  [ `Bsf_not_found
  | `Decoder_not_found
  | `Demuxer_not_found
  | `Encoder_not_found
  | `Eof
  | `Exit
  | `Filter_not_found
  | `Invalid_data
  | `Muxer_not_found
  | `Option_not_found
  | `Patch_welcome
  | `Protocol_not_found
  | `Stream_not_found
  | `Bug
  | `Eagain
  | `Unknown
  | `Experimental
  | `Failure of string ]

external string_of_error : error -> string = "ocaml_avutil_string_of_error"

exception Error of error

let () =
  Printexc.register_printer (function
    | Error err ->
        Some (Printf.sprintf "FFmpeg.Avutils.Error(%s)" (string_of_error err))
    | _ -> None)

let () =
  Callback.register_exception "ffmpeg_exn_error" (Error `Unknown);
  Callback.register "ffmpeg_exn_failure" (fun s -> raise (Error (`Failure s)));
  Callback.register "ffmpeg_gc_finalise" Gc.finalise

external ocaml_avutil_register_lock_manager : unit -> bool
  = "ocaml_avutil_register_lock_manager"
  [@@noalloc]

let () =
  if not (ocaml_avutil_register_lock_manager ()) then
    raise (Error (`Failure "Failed to register lock manager"))

type data =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

let create_data len =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout len

type rational = { num : int; den : int }

external time_base : unit -> rational = "ocaml_avutil_time_base"

module Time_format = struct
  type t = [ `Second | `Millisecond | `Microsecond | `Nanosecond ]
end

module Log = struct
  type level =
    [ `Quiet | `Panic | `Fatal | `Error | `Warning | `Info | `Verbose | `Debug ]

  let int_of_level = function
    | `Quiet -> -8
    | `Panic -> 0
    | `Fatal -> 8
    | `Error -> 16
    | `Warning -> 24
    | `Info -> 32
    | `Verbose -> 40
    | `Debug -> 48

  external set_level : int -> unit = "ocaml_avutil_set_log_level"

  let set_level level = set_level (int_of_level level)

  external setup_log_callback : unit -> unit = "ocaml_avutil_setup_log_callback"
  external process_log : (string -> unit) -> unit = "ocaml_ffmpeg_process_log"

  let log_fn = ref (Printf.printf "%s")
  let log_fn_m = Mutex.create ()

  let set_callback fn =
    setup_log_callback ();
    Mutex.lock log_fn_m;
    log_fn := fn;
    Mutex.unlock log_fn_m

  external clear_callback : unit -> unit = "ocaml_avutil_clear_log_callback"

  let clear_callback () =
    clear_callback ();
    set_callback (Printf.printf "%s")

  let () =
    ignore (Thread.create (fun () -> process_log (fun msg -> !log_fn msg)) ())
end

module Pixel_format = struct
  type t = Pixel_format.t

  external bits : t -> int = "ocaml_avutil_pixelformat_bits_per_pixel"
  external planes : t -> int = "ocaml_avutil_pixelformat_planes"
  external to_string : t -> string = "ocaml_avutil_pixelformat_to_string"
  external of_string : string -> t = "ocaml_avutil_pixelformat_of_string"

  let bits (*?(padding=true)*) p =
    let n = bits p in
    (* TODO: when padding is true we should add the padding *)
    n
end

module Channel_layout = struct
  type t = Channel_layout.t

  external get_description : t -> int -> string
    = "ocaml_avutil_get_channel_layout_description"

  let get_description ?(channels = -1) ch = get_description ch channels

  external find : string -> t = "ocaml_avutil_get_channel_layout"

  external get_nb_channels : t -> int
    = "ocaml_avutil_get_channel_layout_nb_channels"

  external get_default : int -> t = "ocaml_avutil_get_default_channel_layout"
  external get_id : t -> int = "ocaml_avutil_get_channel_layout_id"
end

module Sample_format = struct
  type t = Sample_format.t

  external get_name : t -> string = "ocaml_avutil_get_sample_fmt_name"
  external get_id : t -> int = "ocaml_avutil_get_sample_fmt_id"
  external find : string -> t = "ocaml_avutil_find_sample_fmt"
  external find_id : int -> t = "ocaml_avutil_find_sample_fmt_from_id"
end

module Audio = struct
  external frame_get_sample_format : audio frame -> Sample_format.t
    = "ocaml_avutil_audio_frame_get_sample_format"

  external frame_get_sample_rate : audio frame -> int
    = "ocaml_avutil_audio_frame_get_sample_rate"

  external frame_get_channels : audio frame -> int
    = "ocaml_avutil_audio_frame_get_channels"
end

module Video = struct
  type planes = (data * int) array

  external create_frame : int -> int -> Pixel_format.t -> video frame
    = "ocaml_avutil_video_create_frame"

  external frame_get_linesize : video frame -> int -> int
    = "ocaml_avutil_video_frame_get_linesize"

  external get_frame_planes : video frame -> bool -> planes
    = "ocaml_avutil_video_get_frame_bigarray_planes"

  let frame_visit ~make_writable visit frame =
    visit (get_frame_planes frame make_writable);
    frame

  external frame_get_width : video frame -> int
    = "ocaml_avutil_video_frame_width"

  external frame_get_height : video frame -> int
    = "ocaml_avutil_video_frame_height"

  external frame_get_pixel_format : video frame -> Pixel_format.t
    = "ocaml_avutil_video_frame_get_pixel_format"
end

module Subtitle = struct
  let time_base () = { num = 1; den = 100 }

  external create_frame : int64 -> int64 -> string array -> subtitle frame
    = "ocaml_avutil_subtitle_create_frame"

  let create_frame start_time end_time lines =
    let num_time_base = float_of_int (time_base ()).num in
    let den_time_base = float_of_int (time_base ()).den in

    create_frame
      (Int64.of_float (start_time *. den_time_base /. num_time_base))
      (Int64.of_float (end_time *. den_time_base /. num_time_base))
      (Array.of_list lines)

  external frame_to_lines : subtitle frame -> int64 * int64 * string array
    = "ocaml_avutil_subtitle_to_lines"

  let frame_to_lines t =
    let num_time_base = float_of_int (time_base ()).num in
    let den_time_base = float_of_int (time_base ()).den in

    let s, e, lines = frame_to_lines t in

    Int64.
      ( to_float s *. num_time_base /. den_time_base,
        to_float e *. num_time_base /. den_time_base,
        Array.to_list lines )
end
