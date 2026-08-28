package com.arq.maestria_inventario_products;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class MaestriaInventarioApplicationTests {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void contextLoads() {

	}

	// No aplica descuento
	@Test
	void shouldCreateProductWithoutDiscount_WhenQuantityIsLow() throws Exception {
		String productJson = "{\"name\": \"Teclado\", \"quantity\": 10, \"price\": 100.0}";

		mockMvc.perform(post("/api/products")
						.contentType(MediaType.APPLICATION_JSON)
						.content(productJson))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.id").exists())
				.andExpect(jsonPath("$.name").value("Teclado"))
				.andExpect(jsonPath("$.price").value(100.0));
	}

	//Aplica descuento
	@Test
	void shouldCreateProductWithDiscount_WhenQuantityIsWholesale() throws Exception {
		// 100 unidades activa la WholesaleDiscountStrategy (10% de descuento)
		String productJson = "{\"name\": \"Monitor\", \"quantity\": 100, \"price\": 200.0}";

		mockMvc.perform(post("/api/products")
						.contentType(MediaType.APPLICATION_JSON)
						.content(productJson))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.price").value(180.0)); // 200 - 10% = 180
	}

	@Test
	void shouldReturnAllProducts() throws Exception {
		mockMvc.perform(get("/api/products"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$").isArray());
	}
}