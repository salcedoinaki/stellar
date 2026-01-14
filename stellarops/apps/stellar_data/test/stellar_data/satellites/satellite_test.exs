defmodule StellarData.Satellites.SatelliteTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites.Satellite

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{id: "sat-001"}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without id" do
      attrs = %{name: "Explorer-1"}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "validates mode inclusion" do
      attrs = %{id: "sat-001", mode: :invalid_mode}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).mode
    end

    test "valid modes are accepted" do
      for mode <- [:nominal, :safe, :survival] do
        attrs = %{id: "sat-mode-#{mode}", mode: mode}
        changeset = Satellite.changeset(%Satellite{}, attrs)
        assert changeset.valid?, "Mode #{mode} should be valid"
      end
    end

    test "validates energy range" do
      # Below minimum
      attrs = %{id: "sat-001", energy: -5.0}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).energy

      # Above maximum
      attrs = %{id: "sat-001", energy: 150.0}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      refute changeset.valid?
      assert "must be less than or equal to 100" in errors_on(changeset).energy

      # Valid range
      attrs = %{id: "sat-001", energy: 50.0}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      assert changeset.valid?
    end

    test "validates memory_used range" do
      attrs = %{id: "sat-001", memory_used: -10.0}
      changeset = Satellite.changeset(%Satellite{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).memory_used
    end

    test "accepts all optional fields" do
      attrs = %{
        id: "sat-001",
        name: "Explorer-1",
        mode: :safe,
        energy: 85.5,
        memory_used: 2048.0,
        position_x: 100.5,
        position_y: 200.5,
        position_z: 300.5,
        tle_line1: "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927",
        tle_line2: "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537",
        active: true
      }

      changeset = Satellite.changeset(%Satellite{}, attrs)
      assert changeset.valid?
    end

    test "id must be unique" do
      attrs = %{id: "sat-unique-001", name: "First"}
      {:ok, _satellite} = %Satellite{} |> Satellite.changeset(attrs) |> Repo.insert()

      attrs2 = %{id: "sat-unique-001", name: "Second"}

      assert {:error, changeset} =
               %Satellite{} |> Satellite.changeset(attrs2) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).id
    end

    test "default values are applied" do
      attrs = %{id: "sat-defaults"}
      {:ok, satellite} = %Satellite{} |> Satellite.changeset(attrs) |> Repo.insert()

      assert satellite.mode == :nominal
      assert satellite.energy == 100.0
      assert satellite.memory_used == 0.0
      assert satellite.active == true
    end
  end

  describe "state_changeset/2" do
    test "updates state fields" do
      {:ok, satellite} =
        %Satellite{}
        |> Satellite.changeset(%{id: "state-test-sat"})
        |> Repo.insert()

      changeset = Satellite.state_changeset(satellite, %{
        mode: :survival,
        energy: 50.0,
        memory_used: 1024.0
      })

      assert changeset.valid?
      {:ok, updated} = Repo.update(changeset)
      assert updated.mode == :survival
      assert updated.energy == 50.0
      assert updated.memory_used == 1024.0
    end
  end
end
