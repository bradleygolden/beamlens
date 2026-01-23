# Ignore all Dialyzer warnings for Igniter installer task
# Mix tasks that use Igniter.Mix.Task have false positives from macros
[
  ~r/lib\/mix\/tasks\/beamlens\.install\.ex.*/
]
