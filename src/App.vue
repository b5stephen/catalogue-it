<template>
  <div>
    <Navbar />
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <h1 class="text-3xl font-bold text-gray-900">
          {{pageName}}
        </h1>
      </div>
    </header>
    <main>
      <div class="max-w-7xl mx-auto py-6 px-2 sm:px-6 lg:px-8">
        <router-view/>
      </div>
    </main>
  </div>
</template>

<script lang="ts">
import { defineComponent, computed } from 'vue'
import Navbar from './components/TheNavbar.vue'
import Home from './pages/Home.vue'
import { useRouter} from 'vue-router'

export default defineComponent({
  name: 'App',
  components: {
    
    Navbar,
    Home
  },
  setup: () => {
    const router = useRouter();
    const pageName = computed(() => router.currentRoute.value.params?.name ?? router.currentRoute.value.name); 
    return { pageName }
  }
})
</script>

<style>

</style>
