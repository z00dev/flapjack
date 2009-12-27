#!/usr/bin/env ruby 

require 'sqlite3'

module Flapjack
  module Persistence
    class Sqlite3
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
        @log = @config.log
        connect
      end

      def any_parents_failed?(result)
        rows = @db.execute(%(SELECT count(*) FROM "checks" INNER JOIN "related_checks" ON "related_checks".parent_id = "checks".id AND "related_checks".child_id = #{result.result.check_id};))
        rows.flatten.first != "0"
      end

      def save(result)
        @db.execute(%(UPDATE "checks" SET status = #{result.result.retval} WHERE "id" = #{result.result.check_id};))
        true
      end

      def create_event(result)
        @db.execute(%(INSERT INTO "events" ("check_id", "created_at") VALUES ("#{result.result.check_id}", "#{Time.now}")))
        true
      end

      def save_check(result)
        if check = get_check(result[:id])
          result[:updated_at] = Time.now
          updates = result.map { |key, value| "#{key} = '#{value}'" }.join(', ')
          statement = %(UPDATE "checks" SET #{updates} WHERE "id" = #{result[:id]};)
          @db.execute(statement)
        else
          result[:created_at] = Time.now
          columns, values = columns_and_values_for(result)
          @db.execute(%(INSERT INTO "checks" #{columns} VALUES #{values}))
        end
        result
      end

      def get_check(id)
        result = @db.execute2(%(SELECT * FROM "checks" WHERE id = "#{id}"))
        return nil unless result[1]
        hash = {}
        result[0].each_with_index do |key, index|
          hash[key] = result[1][index]
        end
        hash
      end

      def delete_check(id)
        result = @db.execute2(%(DELETE FROM "checks" WHERE id = "#{id}"))
      end

      def all_checks
        results = @db.execute2(%(SELECT * FROM "checks";))
        
        records = results[1..-1].map do |values|
          hash = {}
          values.each_with_index do |value, index|
            hash[results[0][index]] = value
          end
          hash
        end
        
        records
      end

      private
      def connect
        raise ArgumentError, "Database location wasn't specified" unless @config.database
        @db = ::SQLite3::Database.new(@config.database)

        auto_migrate if @config.auto_migrate
      end

      def auto_migrate
        statements = [
					%(DROP TABLE IF EXISTS "check_templates"),
					%(DROP TABLE IF EXISTS "events"),
					%(DROP TABLE IF EXISTS "related_checks"),
					%(DROP TABLE IF EXISTS "checks"),
					%(DROP TABLE IF EXISTS "nodes"),
					%(PRAGMA table_info('nodes')),
					%(SELECT sqlite_version(*)),
					%(CREATE TABLE "nodes" ("fqdn" VARCHAR(50) NOT NULL, PRIMARY KEY("fqdn"))),
					%(PRAGMA table_info('checks')),
					%(CREATE TABLE "checks" ("created_at" DATETIME, "updated_at" DATETIME, "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "command" TEXT NOT NULL, "params" TEXT DEFAULT NULL, "name" VARCHAR(50) NOT NULL, "enabled" BOOLEAN DEFAULT 'f', "status" INTEGER DEFAULT 0, "deleted_at" DATETIME DEFAULT NULL, "node_fqdn" VARCHAR(50), "check_template_id" INTEGER)),
					%(PRAGMA table_info('related_checks')),
					%(CREATE TABLE "related_checks" ("parent_id" INTEGER, "child_id" INTEGER, "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT)),
					%(PRAGMA table_info('events')),
					%(CREATE TABLE "events" ("created_at" DATETIME, "updated_at" DATETIME, "check_id" INTEGER NOT NULL, "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "deleted_at" DATETIME DEFAULT NULL)),
					%(PRAGMA table_info('check_templates')),
					%(CREATE TABLE "check_templates" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "command" TEXT NOT NULL, "name" VARCHAR(50) NOT NULL, "params" TEXT DEFAULT NULL))
        ]

        statements.each do |statement|
          @db.execute(statement)
        end
      end

      def columns_and_values_for(result)
        @keys = []
        @values = []
        
        result.each_pair do |k,v|
          @keys << k
          @values << v
        end

        keys   = "(\"" + @keys.join(%(", ")) + "\")"
        values = "(\"" + @values.join(%(", ")) + "\")"

        return keys, values
      end

    end
  end
end
