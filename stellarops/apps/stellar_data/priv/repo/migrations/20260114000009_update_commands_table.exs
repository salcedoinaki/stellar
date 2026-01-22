defmodule StellarData.Repo.Migrations.UpdateCommandsTable do
  use Ecto.Migration

  def up do
    # Add new fields to commands table
    alter table(:commands) do
      add_if_not_exists :payload, :map, default: %{}
      add_if_not_exists :sent_at, :utc_datetime_usec
      add_if_not_exists :timeout_ms, :integer, default: 60_000
    end

    # Drop the old status constraint and update enum values
    execute """
    DO $$
    BEGIN
      -- Check if we need to update enum values
      IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'command_status') THEN
        -- Add new enum values
        ALTER TYPE command_status ADD VALUE IF NOT EXISTS 'queued';
        ALTER TYPE command_status ADD VALUE IF NOT EXISTS 'acknowledged';
        ALTER TYPE command_status ADD VALUE IF NOT EXISTS 'executing';
        ALTER TYPE command_status ADD VALUE IF NOT EXISTS 'completed';
        ALTER TYPE command_status ADD VALUE IF NOT EXISTS 'cancelled';
      END IF;
    END $$;
    """

    # Migrate old statuses to new statuses
    execute """
    UPDATE commands
    SET status = CASE status
      WHEN 'pending' THEN 'queued'
      WHEN 'running' THEN 'executing'
      WHEN 'done' THEN 'completed'
      WHEN 'canceled' THEN 'cancelled'
      ELSE status
    END
    WHERE status IN ('pending', 'running', 'done', 'canceled');
    """

    # Add index for active commands
    create_if_not_exists index(:commands, [:status],
      where: "status IN ('queued', 'pending', 'acknowledged', 'executing')",
      name: :commands_active_status_index
    )

    # Add index for scheduled commands
    create_if_not_exists index(:commands, [:scheduled_at],
      where: "status = 'queued' AND scheduled_at IS NOT NULL",
      name: :commands_scheduled_index
    )
  end

  def down do
    drop_if_exists index(:commands, [:status], name: :commands_active_status_index)
    drop_if_exists index(:commands, [:scheduled_at], name: :commands_scheduled_index)

    alter table(:commands) do
      remove_if_exists :payload, :map
      remove_if_exists :sent_at, :utc_datetime_usec
      remove_if_exists :timeout_ms, :integer
    end
  end
end
