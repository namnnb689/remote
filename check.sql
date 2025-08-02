SELECT inhrelid::regclass AS partition_name
FROM pg_inherits
WHERE inhparent = 'vit_trans.wellness_attributes_partition'::regclass;


\d+ vit_trans.wellness_attributes_partition
