# Load support modules before running tests
Code.require_file("support/conn_case.ex", __DIR__)
Code.require_file("support/channel_case.ex", __DIR__)

ExUnit.start()
