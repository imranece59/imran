-- Modified query to exclude self-dependencies
WITH view_dependencies AS (
    SELECT 
        source_ns.nspname || '.' || source.relname AS parent_view,
        dependent_ns.nspname || '.' || dependent.relname AS dependent_view
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class dependent ON dependent.oid = r.ev_class
    JOIN pg_namespace dependent_ns ON dependent_ns.oid = dependent.relnamespace
    JOIN pg_class source ON source.oid = d.refobjid
    JOIN pg_namespace source_ns ON source_ns.oid = source.relnamespace
    WHERE source.relkind IN ('v', 'm')
    AND dependent.relkind IN ('v', 'm')
    AND source_ns.nspname NOT IN ('pg_catalog', 'information_schema')
    AND source.oid != dependent.oid  -- Exclude self-dependencies
)
SELECT 
    parent_view,
    LISTAGG(dependent_view, ', ') WITHIN GROUP (ORDER BY dependent_view) AS dependent_views,
    COUNT(*) AS dependency_count
FROM view_dependencies
WHERE parent_view IN (
    'reporting.customer_summary_v',
    'analytics.sales_metrics_v'
)
GROUP BY parent_view
ORDER BY parent_view;