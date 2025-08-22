-- Find what views depend on your target views
SELECT DISTINCT
    table_schema || '.' || table_name AS parent_view,
    view_schema || '.' || view_name AS dependent_view
FROM information_schema.view_table_usage
WHERE table_schema || '.' || table_name IN (
    'reporting.customer_summary_v',
    'analytics.sales_metrics_v'
)
AND table_name != view_name  -- Exclude self-references
ORDER BY parent_view, dependent_view;

-- Alternative using pg_class and pg_depend (Redshift-specific)
SELECT DISTINCT
    src_schema.nspname || '.' || src_table.relname AS parent_view,
    dep_schema.nspname || '.' || dep_table.relname AS dependent_view
FROM pg_depend d
JOIN pg_class src_table ON src_table.oid = d.refobjid
JOIN pg_namespace src_schema ON src_schema.oid = src_table.relnamespace
JOIN pg_class dep_table ON dep_table.oid = d.objid
JOIN pg_namespace dep_schema ON dep_schema.oid = dep_table.relnamespace
WHERE src_table.relkind = 'v'
AND dep_table.relkind = 'v'
AND src_schema.nspname || '.' || src_table.relname IN (
    'reporting.customer_summary_v',
    'analytics.sales_metrics_v'
)
AND src_table.oid != dep_table.oid;

-- Using Redshift system view
SELECT DISTINCT
    ref.schema || '.' || ref.table AS parent_view,
    base.schema || '.' || base.table AS dependent_view
FROM svv_table_info base
JOIN svv_table_info ref ON base.table_id = ref.table_id
WHERE ref.schema || '.' || ref.table IN (
    'reporting.customer_summary_v', 
    'analytics.sales_metrics_v'
)
AND base.table_type = 'VIEW'
AND ref.table_type = 'VIEW';