///|
test "download deny cancels an item updated before the decision" {
  inspect(
    download_deny_after_update_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=0
    ),
  )
}

///|
test "invalid download response fails closed" {
  inspect(
    download_invalid_response_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=-1
    ),
  )
}

///|
test "empty download response fails closed" {
  inspect(
    download_empty_response_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=-1
    ),
  )
}

///|
test "denied download policy leaves cancellation to CEF" {
  inspect(
    denied_download_policy_trace(),
    content="handled=0,before_continue=0,before_release=0",
  )
}

///|
test "unpublished download request leaves cancellation to CEF" {
  inspect(
    unpublished_download_request_trace(),
    content="handled=0,before_continue=0,before_release=1",
  )
}

///|
test "download cancellation completes once across response and destroy" {
  inspect(
    download_single_completion_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=1,respond=0,repeat=-14
    ),
  )
}

///|
test "download command wins over a later allow decision" {
  inspect(
    download_command_beats_allow_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=1,command=0,respond=-14
    ),
  )
}

///|
test "download deny is remembered until its item callback arrives" {
  inspect(
    download_deny_before_update_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=0
    ),
  )
}
