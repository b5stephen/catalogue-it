import { createWebHashHistory, createRouter, RouteRecordRaw } from 'vue-router'

import Home from './pages/Home.vue'
import Catalogue from './pages/Catalogue.vue'

const routes: RouteRecordRaw[] = [
    {
        path: '/',
        name: 'Home',
        component: Home,        
    },
    {
        path: '/catalogue/:name',
        name: 'Catalogue',
        component: Catalogue
    }
]


const router = createRouter({
    history: createWebHashHistory(),
    routes,
})

export default router;
