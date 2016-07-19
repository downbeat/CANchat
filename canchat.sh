#!/bin/bash
# CAN Chat!
# Russ Bielawski


CANIF=can0
CANPIPE=/tmp/canpipe

STX="02"
ETX="03"
# Unused for now.
#CMD_REQ_JOIN="00"
#CMD_NAME_TAKEN="01"
CMD_MESSAGE="02"

if [ ! $1 ]; then
   echo "Usage: $0 <name>"
   exit 1
fi
user_handle=$1
if [ ${#user_handle} -gt 14 ]; then
   echo "Name is too long (14 characters max)!"
   exit 1
fi


char2hex() {
   # Return space for unimplemented digit.
   local ascii="20"
   local raw=$1
   # The cases are collapsed to a single line to hide my shame.
   case "$raw" in
      '!') ascii="21";; '"') ascii="22";; '#') ascii="23";; '$') ascii="24";; '%') ascii="25";; '&') ascii="26";; "\'") ascii="27";; '(') ascii="28";; ')') ascii="29";; '*') ascii="2A";; '+') ascii="2B";; ',') ascii="2C";; '-') ascii="2D";; '.') ascii="2E";; '/') ascii="2F";; '0') ascii="30";; '1') ascii="31";; '2') ascii="32";; '3') ascii="33";; '4') ascii="34";; '5') ascii="35";; '6') ascii="36";; '7') ascii="37";; '8') ascii="38";; '9') ascii="39";; ':') ascii="3A";; ';') ascii="3B";; '?') ascii="3F";; '@') ascii="40";; 'A') ascii="41";; 'B') ascii="42";; 'C') ascii="43";; 'D') ascii="44";; 'E') ascii="45";; 'F') ascii="46";; 'G') ascii="47";; 'H') ascii="48";; 'I') ascii="49";; 'J') ascii="4A";; 'K') ascii="4B";; 'L') ascii="4C";; 'M') ascii="4D";; 'N') ascii="4E";; 'O') ascii="4F";; 'P') ascii="50";; 'Q') ascii="51";; 'R') ascii="52";; 'S') ascii="53";; 'T') ascii="54";; 'U') ascii="55";; 'V') ascii="56";; 'W') ascii="57";; 'X') ascii="58";; 'Y') ascii="59";; 'Z') ascii="5A";; '[') ascii="5B";; "\\") ascii="5C";; ']') ascii="5D";; '^') ascii="5E";; '_') ascii="5F";; 'a') ascii="61";; 'b') ascii="62";; 'c') ascii="63";; 'd') ascii="64";; 'e') ascii="65";; 'f') ascii="66";; 'g') ascii="67";; 'h') ascii="68";; 'i') ascii="69";; 'j') ascii="6A";; 'k') ascii="6B";; 'l') ascii="6C";; 'm') ascii="6D";; 'n') ascii="6E";; 'o') ascii="6F";; 'p') ascii="70";; 'q') ascii="71";; 'r') ascii="72";; 's') ascii="73";; 't') ascii="74";; 'u') ascii="75";; 'v') ascii="76";; 'w') ascii="77";; 'x') ascii="78";; 'y') ascii="79";; 'z') ascii="7A";; '{') ascii="7B";; '|') ascii="7C";; '}') ascii="7D";; '~') ascii="7E";;
      *) ascii="20";;
   esac
   # Return the 2 digit hex value as a string (second parameter).
   eval "$2=$ascii"
}

hex2char() {
   # Return space for unimplemented digit.
   local ascii="$1"
   local raw=" "
   raw=`echo -en "\\x$ascii"`
   # Return the char as a string (second parameter).
   eval "$2=$raw"
   # For some reason, this can't handle spaces properly.  Just handle in caller!
}


# These associative arrays are where data is being assembled.
declare -A username
declare -A message_data
declare -A num_frames_rxd


# Username is sent as 2 CAN messages.  The first CAN frame includes the "Start of Text" symbol,
# the "CMD_MESSAGE" symbol and the first 6 bytes of the user name.  The second frame contains
# the remaining 8 bytes of the username.  The username cannot exceed 14 charaters.
USER_PART_0=$STX$CMD_MESSAGE
USER_PART_1=""
user_handle_temp=$user_handle
for((ii=0; ii<6; ii++)); do
   if [ ${#user_handle_temp} -gt 0 ]; then
      raw_char=${user_handle_temp:0:1}
      user_handle_temp=${user_handle_temp:1:${#user_handle_temp}-1}
      char2hex "$raw_char" ascii_char
      USER_PART_0=$USER_PART_0$ascii_char
   fi
done
for((ii=0; ii<8; ii++)); do
   if [ ${#user_handle_temp} -gt 0 ]; then
      raw_char=${user_handle_temp:0:1}
      user_handle_temp=${user_handle_temp:1:${#user_handle_temp}-1}
      char2hex "$raw_char" ascii_char
      USER_PART_1=$USER_PART_1$ascii_char
   fi
done
END_MESSAGE_FRAME=$ETX

echo "Welcome, $user_handle!"


# Connect candump to a named pipe for reading from CAN in the background
trap "rm -f $CANPIPE" EXIT SIGKILL
# Just delete the pipe if it already exists.
rm -f $CANPIPE
mkfifo $CANPIPE;

# This is ugly, and probably the source of my duplicate data!
exec `while [ 1 ]; do candump -L $CANIF,600:700 >> /tmp/canpipe; done`&


while [ 1 ]; do
   # This keeps the pipe open.
   # From Stack Overflow.  How does it work!?
   exec 3<$CANPIPE
   exec 4<&-

   ################ SEND LOGIC ###################

   read -t 5 user_message
   msg=$user_message
   # If the user entered a message, send it out.
   if [ ${#msg} -gt 0 ]; then
      # Create a random CAN ID in the range 0x600-0x6FF
      canid=`printf 6%02X $((RANDOM%256))`
      cansend $CANIF $canid#$USER_PART_0
      # Always send the second username frame, even if it's 0 length.
      cansend $CANIF $canid#$USER_PART_1
      # Create the data for the CAN frames.
      while [ ${#msg} -gt 0 ]; do
         can_data=""
         for((ii=0; ii<8; ii++)); do
            if [ ${#msg} -gt 0 ]; then
               raw_char=${msg:0:1}
               msg=${msg:1:${#msg}-1}
               char2hex "$raw_char" ascii_char
               can_data=$can_data$ascii_char
            fi
         done
         cansend $CANIF $canid#$can_data
      done
      # One final CAN frame with the "End of Text" character.
      cansend $CANIF $canid#$END_MESSAGE_FRAME
      #echo "["$user_handle"]": $user_message
   fi

   ################ RECEIVE LOGIC ################

   # Just stick some random string into can_frame to pass the while test the first time.
   can_frame="asdf";
   can_frame_last="asdf";
   while [ ${#can_frame} -gt 0 ]; do
      read -t 0.1 can_frame <$CANPIPE
      if [ ${#can_frame} -gt 0 ]; then
         # For some reason, I am receiving duplicate data from the pipe.  If that happens, just discard it.
         if [ "$can_frame" != "$can_frame_last" ]; then
            for ii in $can_frame; do
               can_id_and_data=$ii
            done
            can_id=${can_id_and_data:0:3}
            can_data=${can_id_and_data:4:${#can_id_and_data}-4}
            # Check if this is a Start of Text frame.
            if [ "$STX" == "${can_data:0:2}" ]; then
               if [ "$CMD_MESSAGE" == "${can_data:2:2}" ]; then
                  # Activate this buffer.
                  num_frames_rxd[$can_id]=1
                  username[$can_id]=${can_data:4:12}
                  message_data[$can_id]=""
               fi
            elif [ ${num_frames_rxd[$can_id]} -eq 1 ]; then
               # Grab second username frame
               num_frames_rxd[$can_id]=2
               username[$can_id]=${username[$can_id]}${can_data}
            elif [ ${num_frames_rxd[$can_id]} -gt 1 ]; then
               # Check if this is a End of Text frame.
               if [ "$ETX" == "${can_data:0:2}" ]; then
                  # Message received: convert to ASCII and print the message.
                  hex_username="${username[$can_id]}"
                  hex_msg="${message_data[$can_id]}"
                  username=""
                  msg=""
                  while [ ${#hex_username} -gt 0 ]; do
                     ascii_char=${hex_username:0:2}
                     hex_username=${hex_username:2:${#hex_username}-2}
                     hex2char "$ascii_char" raw_char
                     username=$username$raw_char
                  done
                  while [ ${#hex_msg} -gt 0 ]; do
                     ascii_char=${hex_msg:0:2}
                     hex_msg=${hex_msg:2:${#hex_msg}-2}
                     hex2char "$ascii_char" raw_char
                     # For some reason, hex2char can't handle spaces properly.  Handle here.
                     if [ ${#raw_char} -eq 0 ]; then
                        msg=$msg' '
                     else
                        msg="$msg$raw_char"
                     fi
                  done
                  #username_string="[$username]:"
                  # Print the message!
                  #printf "%15s %s\n" "$username_string" "$msg"
                  echo "[$username]: $msg"
                  # Deactivate this buffer.
                  num_frames_rxd[$can_id]=0
               else
                  # Store message data.
                  message_data[$can_id]=${message_data[$can_id]}${can_data}
                  num_frames_rxd[$can_id]=$((${num_frames_rxd[$can_id]}+1))
               fi
            fi
         fi
         can_frame_last=$can_frame
      fi
   done


   # From Stack Overflow.  How does it work!?
   exec 4<&3
   exec 3<&-
done
