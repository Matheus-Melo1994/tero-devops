package repository

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
	"gorm.io/plugin/opentelemetry/tracing"
	"retail-store/catalog/config"
	"retail-store/catalog/model"
)

type Database struct {
	DB *gorm.DB
}

type CatalogRepository interface {
	GetProducts(tags []string, order string, pageNum, pageSize int, ctx context.Context) ([]model.Product, error)
	CountProducts(tags []string, ctx context.Context) (int, error)
	GetProduct(id string, ctx context.Context) (*model.Product, error)
	GetTags(ctx context.Context) ([]model.Tag, error)
}

func createPostgreSQLDatabase(config config.DatabaseConfiguration) (*gorm.DB, error) {
	host := config.Endpoint
	port := "5432"
	if parts := strings.SplitN(config.Endpoint, ":", 2); len(parts) == 2 {
		host = parts[0]
		port = parts[1]
	}
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable connect_timeout=%d",
		host, port, config.User, config.Password, config.Name, config.ConnectTimeout)

	var db *gorm.DB
	var err error

	for i := 0; i < 6; i++ {
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: gormlogger.Default.LogMode(gormlogger.Silent)})
		if err == nil {
			return db, nil
		}
		slog.Warn("Waiting for PostgreSQL", "attempt", i+1)
		time.Sleep(5 * time.Second)
	}

	return nil, err
}

func NewRepository(config config.DatabaseConfiguration) (CatalogRepository, error) {
	var db *gorm.DB
	var err error

	switch config.Type {
	case "postgres":
		slog.Info("Using postgres database")
		db, err = createPostgreSQLDatabase(config)
	default:
		slog.Info("Using in-memory database")
		db, err = gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{Logger: gormlogger.Default.LogMode(gormlogger.Silent)})
	}

	if err != nil {
		return nil, fmt.Errorf("failed to connect database: %w", err)
	}

	if err := db.Use(tracing.NewPlugin(tracing.WithoutMetrics())); err != nil {
		slog.Error("Database tracing setup failed", "error_type", fmt.Sprintf("%T", err))
		return nil, err
	}

	slog.Info("Running database migration")

	// Migrate the schema
	if err := db.AutoMigrate(&model.Product{}); err != nil {
		slog.Error("Database migration failed", "error_type", fmt.Sprintf("%T", err))
		return nil, err
	}

	slog.Info("Database migration complete")

	products, err := LoadProductData()
	if err != nil {
		slog.Error("Loading product data failed", "error_type", fmt.Sprintf("%T", err))
		return nil, err
	}

	tags, err := LoadProductTagData()
	if err != nil {
		slog.Error("Loading tag data failed", "error_type", fmt.Sprintf("%T", err))
		return nil, err
	}

	tagMap := make(map[string]model.Tag)

	for _, tag := range tags {
		tagEntity := model.Tag{Name: tag.Name, DisplayName: tag.DisplayName}
		if err := db.Save(tagEntity).Error; err != nil {
			slog.Error("Saving catalog tag failed", "error_type", fmt.Sprintf("%T", err))
			return nil, err
		}

		tagMap[tag.Name] = tagEntity
	}

	for _, product := range products {
		var result model.Product
		r := db.
			Where("id = ?", product.ID).
			Limit(1).
			Find(&result)

		if r.RowsAffected > 0 {
			continue
		}

		productTags := []model.Tag{}
		for _, tag := range product.Tags {
			productTags = append(productTags, tagMap[tag])
		}

		if err := db.Create(&model.Product{
			ID:          product.ID,
			Name:        product.Name,
			Description: product.Description,
			Price:       product.Price,
			Tags:        productTags,
		}).Error; err != nil {
			slog.Error("Saving catalog product failed", "error_type", fmt.Sprintf("%T", err))
			return nil, err
		}
	}

	return &Database{
		DB: db,
	}, nil
}

func (db *Database) GetProducts(tags []string, order string, pageNum, pageSize int, ctx context.Context) ([]model.Product, error) {
	products := []model.Product{}

	query := db.DB.Preload("Tags")

	// Apply tags filter if provided
	if len(tags) > 0 {
		query = query.Joins("JOIN product_tags ON product_tags.product_id = products.id").
			Joins("JOIN tags ON tags.name = product_tags.tag_name").
			Where("tags.name IN ?", tags).
			Group("products.id")
	}

	// Apply ordering
	switch order {
	case "price_asc":
		query = query.Order("price asc")
	case "price_desc":
		query = query.Order("price desc")
	default:
		query = query.Order("products.name asc") // default ordering
	}

	// Apply pagination
	offset := (pageNum - 1) * pageSize
	query = query.Offset(offset).Limit(pageSize)

	// Execute the query
	err := query.WithContext(ctx).Find(&products).Error
	if err != nil {
		slog.Error("Product list query failed", "error_type", fmt.Sprintf("%T", err))
		return nil, err
	}

	return products, err
}

func (db *Database) GetProduct(id string, ctx context.Context) (*model.Product, error) {
	product := model.Product{}

	err := db.DB.WithContext(ctx).
		Preload("Tags").
		Where("id = ?", id).
		First(&product).Error

	if err != nil {
		if err != gorm.ErrRecordNotFound {
			slog.Error("Product lookup failed", "error_type", fmt.Sprintf("%T", err))
		}
		return nil, err
	}

	return &product, err
}

func (db *Database) CountProducts(tags []string, ctx context.Context) (int, error) {
	var count int64

	query := db.DB.WithContext(ctx).Model(&model.Product{})

	// Apply tags filter if provided
	if len(tags) > 0 {
		query = query.Joins("JOIN product_tags ON product_tags.product_id = products.id").
			Joins("JOIN tags ON tags.name = product_tags.tag_name").
			Where("tags.name IN ?", tags).
			Group("products.id")
	}

	err := query.Count(&count).Error
	if err != nil {
		slog.Error("Product count query failed", "error_type", fmt.Sprintf("%T", err))
		return 0, err
	}

	return int(count), nil
}

func (db *Database) GetTags(ctx context.Context) ([]model.Tag, error) {
	tags := []model.Tag{}

	err := db.DB.WithContext(ctx).
		Model(&model.Tag{}).
		Order("display_name asc"). // Order by display name alphabetically
		Find(&tags).Error

	if err != nil {
		slog.Error("Tag query failed", "error_type", fmt.Sprintf("%T", err))
		return nil, fmt.Errorf("failed to fetch tags: %w", err)
	}

	return tags, err
}
