defmodule BeamlensTest do
  use ExUnit.Case

  describe "Beamlens.child_spec/1" do
    test "returns valid child spec" do
      spec = Beamlens.child_spec([])

      assert spec.id == Beamlens
      assert spec.start == {Beamlens, :start_link, [[]]}
      assert spec.type == :supervisor
    end

    test "passes options to start_link" do
      opts = [schedules: [{:default, "*/5 * * * *"}]]
      spec = Beamlens.child_spec(opts)

      assert spec.start == {Beamlens, :start_link, [opts]}
    end
  end
end
