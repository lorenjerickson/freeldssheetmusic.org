ruby script/runner -e production "Cache.clear!; Session.delete_all"
echo m4m
A=`date`
B=`echo $A | tr -d \\n`
mysqldump -uwilkboar_m4m wilkboar_m4m -p > "snap$B.sql"
gzip "snap$B.sql"
